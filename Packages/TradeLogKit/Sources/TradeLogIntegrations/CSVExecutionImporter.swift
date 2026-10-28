import Foundation
import TradeLogCore

/// Maps CSV column *header names* to execution fields.
public struct CSVColumnMapping: Codable, Sendable, Hashable {
    public var date: String
    public var symbol: String
    public var side: String
    public var quantity: String
    public var price: String
    public var fee: String?
    public var feeCurrency: String?
    public var externalID: String?
    /// `DateFormatter` pattern (en_US_POSIX). nil = try ISO8601, epoch, then common formats.
    public var dateFormat: String?
    /// Zone for dates without an offset (nil = UTC). A trailing "EST"/"EDT"/"PST"/... token in the
    /// cell overrides it.
    public var timeZoneID: String?
    public var defaultAssetClass: AssetClass

    public init(
        date: String, symbol: String, side: String, quantity: String, price: String,
        fee: String? = nil, feeCurrency: String? = nil, externalID: String? = nil,
        dateFormat: String? = nil, timeZoneID: String? = nil, defaultAssetClass: AssetClass
    ) {
        self.date = date
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.feeCurrency = feeCurrency
        self.externalID = externalID
        self.dateFormat = dateFormat
        self.timeZoneID = timeZoneID
        self.defaultAssetClass = defaultAssetClass
    }
}

/// Generic CSV import (Webull, Moomoo, Coinbase, ... exports) driven by a column mapping.
public enum CSVExecutionImporter {

    // MARK: Headers & guessing

    /// Header cells of the first non-empty row.
    public static func headers(in text: String) -> [String] {
        let rows = CSVParser.parse(text)
        guard let index = headerRowIndex(rows) else { return [] }
        return rows[index].map(cleanHeader)
    }

    private static func normalized(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let dateCandidates = [
        "filledtime", "filltime", "executiontime", "executedat", "tradetime", "tradedate", "transactiontime",
        "datetime", "date", "time", "timestamp", "createtime", "createdat", "placedtime", "ordertime",
    ]
    private static let symbolCandidates = ["symbol", "ticker", "instrument", "stockcode", "code", "pair", "market", "asset", "name"]
    private static let sideCandidates = ["side", "buysell", "bs", "action", "direction", "transactiontype", "tradetype", "type"]
    private static let quantityCandidates = [
        "filledqty", "fillqty", "filledquantity", "fillquantity", "executedqty", "execqty", "filled",
        "quantity", "qty", "shares", "totalqty", "size", "amount",
    ]
    private static let priceCandidates = [
        "avgprice", "avgfillprice", "fillprice", "filledprice", "executionprice", "execprice", "tradeprice",
        "averageprice", "price", "orderprice",
    ]
    private static let feeCandidates = ["fee", "fees", "totalfees", "totalfee", "commission", "commissions", "tradefee"]
    private static let feeCurrencyCandidates = ["feecurrency", "feeasset", "commissionasset", "feecoin", "commissioncurrency"]
    private static let idCandidates = ["tradeid", "executionid", "execid", "transactionid", "id", "orderid", "orderno", "ordernumber"]

    /// Best-effort mapping from header names; nil when a required column (date, symbol, side,
    /// quantity, price) cannot be found.
    public static func guessMapping(headers: [String], defaultAssetClass: AssetClass) -> CSVColumnMapping? {
        let cleaned = headers.map(cleanHeader)
        var used = Set<Int>()

        func find(_ candidates: [String]) -> String? {
            for candidate in candidates {
                for (index, header) in cleaned.enumerated() where !used.contains(index) && normalized(header) == candidate {
                    used.insert(index)
                    return header
                }
            }
            return nil
        }

        guard let date = find(dateCandidates),
              let symbol = find(symbolCandidates),
              let side = find(sideCandidates),
              let quantity = find(quantityCandidates),
              let price = find(priceCandidates) else { return nil }
        return CSVColumnMapping(
            date: date, symbol: symbol, side: side, quantity: quantity, price: price,
            fee: find(feeCandidates),
            feeCurrency: find(feeCurrencyCandidates),
            externalID: find(idCandidates),
            defaultAssetClass: defaultAssetClass
        )
    }

    // MARK: Parsing

    /// Parses data rows (the header row is skipped). Rows that cannot be read are skipped; throws
    /// `IntegrationError.decoding` when a mapped column is missing or when no row could be parsed.
    public static func parse(_ text: String, mapping: CSVColumnMapping, source: String) throws -> [ImportedExecution] {
        let rows = CSVParser.parse(text)
        guard let headerIndex = headerRowIndex(rows) else {
            throw IntegrationError.decoding("CSV has no header row")
        }
        let header = rows[headerIndex].map(cleanHeader)

        func column(_ name: String?) -> Int? {
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            if let exact = header.firstIndex(of: name) { return exact }
            let target = normalized(name)
            return header.firstIndex { normalized($0) == target }
        }
        func requiredColumn(_ name: String) throws -> Int {
            guard let index = column(name) else {
                throw IntegrationError.decoding("Column '\(name)' not found in CSV header")
            }
            return index
        }

        let dateCol = try requiredColumn(mapping.date)
        let symbolCol = try requiredColumn(mapping.symbol)
        let sideCol = try requiredColumn(mapping.side)
        let quantityCol = try requiredColumn(mapping.quantity)
        let priceCol = try requiredColumn(mapping.price)
        let feeCol = column(mapping.fee)
        let feeCurrencyCol = column(mapping.feeCurrency)
        let idCol = column(mapping.externalID)

        let dateParser = CSVDateParser(format: mapping.dateFormat, timeZoneID: mapping.timeZoneID)

        var occurrences: [String: Int] = [:]
        var result: [ImportedExecution] = []

        for row in rows.dropFirst(headerIndex + 1) {
            func cell(_ index: Int?) -> String {
                guard let index = index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }

            guard let date = dateParser.parse(cell(dateCol)) else { continue }
            let symbol = normalizeSymbol(cell(symbolCol), assetClass: mapping.defaultAssetClass)
            guard !symbol.isEmpty else { continue }
            guard let signedQuantity = number(cell(quantityCol)), signedQuantity != 0 else { continue }
            guard let rawPrice = number(cell(priceCol)) else { continue }
            let price = abs(rawPrice)
            guard price > 0 else { continue }

            let sideText = cell(sideCol)
            let side: ExecutionSide
            if sideText.isEmpty {
                side = signedQuantity < 0 ? .sell : .buy
            } else if let parsed = parseSide(sideText) {
                side = parsed
            } else {
                continue
            }

            let fee = abs(number(cell(feeCol)) ?? 0)
            let feeCurrency = cell(feeCurrencyCol)

            let baseID: String
            let provided = cell(idCol)
            if !provided.isEmpty {
                baseID = provided
            } else {
                baseID = fnv1aHex(row.joined(separator: "\u{1F}"))
            }
            let count = (occurrences[baseID] ?? 0) + 1
            occurrences[baseID] = count
            let externalID = count == 1 ? baseID : "\(baseID)#\(count)"

            result.append(ImportedExecution(
                source: source,
                externalID: externalID,
                symbol: symbol,
                assetClass: mapping.defaultAssetClass,
                side: side,
                quantity: abs(signedQuantity),
                price: price,
                fee: fee,
                feeCurrency: feeCurrency.isEmpty ? nil : feeCurrency,
                date: date
            ))
        }

        guard !result.isEmpty else {
            throw IntegrationError.decoding("No executions could be parsed from the CSV")
        }
        return result
    }

    // MARK: Helpers

    private static func headerRowIndex(_ rows: [[String]]) -> Int? {
        rows.firstIndex { row in
            row.contains { cell in !cell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private static func cleanHeader(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseSide(_ raw: String) -> ExecutionSide? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("buy") { return .buy }
        if s.hasPrefix("sell") { return .sell }
        switch s {
        case "b", "bought", "long", "bto", "bot": return .buy
        case "s", "sold", "short", "sto", "sld": return .sell
        default: return nil
        }
    }

    /// Strips "$" and thousands separators; "(12.5)" is negative.
    static func number(_ raw: String) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("+") { s.removeFirst() }
        guard !s.isEmpty, let value = Decimal(string: s) else { return nil }
        return negative ? -value : value
    }

    /// "US.AAPL" / "NASDAQ:AAPL" -> "AAPL"; crypto pairs "BTC/USDT" -> "BTCUSDT".
    static func normalizeSymbol(_ raw: String, assetClass: AssetClass) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let colon = s.lastIndex(of: ":") { s = String(s[s.index(after: colon)...]) }
        if s.hasPrefix("US.") { s = String(s.dropFirst(3)) }
        if assetClass != .usStock {
            s = s.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "-", with: "")
        }
        return s
    }

    /// FNV-1a 64-bit, hex (stable across runs, unlike `hashValue`).
    static func fnv1aHex(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

/// Date cell parser: custom format, or ISO8601 / epoch / common US + ISO-like formats.
private struct CSVDateParser {
    private static let zoneOffsets: [String: Int] = [
        "UTC": 0, "GMT": 0, "Z": 0,
        "EST": -18000, "EDT": -14400, "CST": -21600, "CDT": -18000,
        "MST": -25200, "MDT": -21600, "PST": -28800, "PDT": -25200,
    ]

    private static let commonFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy hh:mm:ss a", "MM/dd/yyyy hh:mm a", "MM/dd/yyyy",
        "M/d/yyyy HH:mm:ss", "M/d/yyyy H:mm", "M/d/yyyy h:mm:ss a", "M/d/yyyy h:mm a", "M/d/yyyy",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
        "MMM d, yyyy h:mm:ss a", "MMM d, yyyy HH:mm:ss", "MMM d, yyyy",
    ]

    private let custom: Bool
    private let formatters: [DateFormatter]
    private let defaultZone: TimeZone

    init(format: String?, timeZoneID: String?) {
        defaultZone = TimeZone(identifier: timeZoneID ?? "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let patterns: [String]
        if let format = format, !format.isEmpty {
            custom = true
            patterns = [format]
        } else {
            custom = false
            patterns = Self.commonFormats
        }
        formatters = patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = pattern
            return formatter
        }
    }

    func parse(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        if !custom {
            if text.allSatisfy({ $0.isNumber }), text.count == 10 || text.count == 13, let value = Double(text) {
                return Date(timeIntervalSince1970: text.count == 13 ? value / 1000 : value)
            }
            if let iso = DateParsing.iso8601(text) { return iso }
        }

        var zone = defaultZone
        let parts = text.split(separator: " ")
        if parts.count > 1, let last = parts.last, last.count <= 4, last.allSatisfy({ $0.isLetter }),
           let offset = Self.zoneOffsets[last.uppercased()] {
            zone = TimeZone(secondsFromGMT: offset) ?? defaultZone
            text = parts.dropLast().joined(separator: " ")
        }

        for formatter in formatters {
            formatter.timeZone = zone
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
