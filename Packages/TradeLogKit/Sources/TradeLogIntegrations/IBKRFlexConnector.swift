import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
import TradeLogCore

/// Interactive Brokers Flex Web Service v3 (trade report XML). Read-only.
///
/// Flow: `SendRequest?t=TOKEN&q=QUERYID&v=3` -> `<ReferenceCode>` + `<Url>`; then
/// `{Url}?q=REFERENCE&t=TOKEN&v=3` returns the `FlexQueryResponse`. While the statement is still
/// being generated IB answers with ErrorCode 1019 and we retry (5 retries, 3 s apart by default).
///
/// Assumptions / notes:
/// - Only `<Trade>` (and `<TradeConfirm>`) elements are read. If the query emits `levelOfDetail`,
///   only `EXECUTION` rows are used (so ORDER / CLOSED_LOT summaries do not double count).
/// - `assetCategory` STK -> `.usStock`, CRYPTO -> `.cryptoSpot`; every other category is skipped.
///   Crypto symbols become base + currency (e.g. "BTC" + "USD" -> "BTCUSD").
/// - IB timestamps carry no zone and are in the account's configured timezone; **America/New_York
///   is assumed**. `dateTime` ("yyyyMMdd;HHmmss") is preferred, else `tradeDate` + `tradeTime`.
/// - quantity is signed in IB (negative for sells) -> magnitude is stored; fee = abs(ibCommission).
/// - Trades in non-USD currencies are kept as-is (price/fee in that currency); the app treats
///   prices as USD, so use a USD-only Flex query.
public struct IBKRFlexConnector: BrokerConnector {
    public static let connectorID = "ibkr"
    public static let displayName = "Interactive Brokers (Flex)"
    public static let credentialFields: [CredentialField] = [
        CredentialField(key: "token", label: "Flex Web Service Token", isSecret: true),
        CredentialField(key: "queryID", label: "Flex Query ID", isSecret: false),
    ]

    static let sendRequestURL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/SendRequest"
    static let defaultStatementURL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService/GetStatement"

    private let credentials: [String: String]
    private let http: HTTPClient
    private let maxRetries: Int
    private let retryDelaySeconds: Double

    public init(credentials: [String: String], session: HTTPClient) {
        self.init(credentials: credentials, session: session, maxRetries: 5, retryDelaySeconds: 3)
    }

    /// Retry parameters exposed for tests.
    public init(credentials: [String: String], session: HTTPClient, maxRetries: Int, retryDelaySeconds: Double) {
        self.credentials = credentials
        self.http = session
        self.maxRetries = max(0, maxRetries)
        self.retryDelaySeconds = max(0, retryDelaySeconds)
    }

    public func fetchExecutions(since: Date?) async throws -> [ImportedExecution] {
        guard let token = credentials["token"]?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            throw IntegrationError.missingCredential("token")
        }
        guard let queryID = credentials["queryID"]?.trimmingCharacters(in: .whitespaces), !queryID.isEmpty else {
            throw IntegrationError.missingCredential("queryID")
        }
        let headers = ["User-Agent": "TradeLog/1.0"]

        // Step 1: request the statement.
        let step1 = QueryString.build([("t", token), ("q", queryID), ("v", "3")])
        let sendData = try await http.sendData(try RequestFactory.get("\(Self.sendRequestURL)?\(step1)", headers: headers))
        let sendResponse = try FlexXMLParser.parse(sendData)
        guard sendResponse.values["Status"] == "Success", let reference = sendResponse.values["ReferenceCode"] else {
            throw IntegrationError.http(
                status: Int(sendResponse.values["ErrorCode"] ?? "") ?? 0,
                body: sendResponse.values["ErrorMessage"] ?? "Flex SendRequest failed"
            )
        }
        let statementURL = sendResponse.values["Url"] ?? Self.defaultStatementURL

        // Step 2: download it (retry while IB is still generating).
        let step2 = QueryString.build([("q", reference), ("t", token), ("v", "3")])
        var attempt = 0
        while true {
            let data = try await http.sendData(try RequestFactory.get("\(statementURL)?\(step2)", headers: headers))
            let parsed = try FlexXMLParser.parse(data)
            if parsed.rootName == "FlexQueryResponse" {
                return try Self.executions(fromParsed: parsed, since: since)
            }
            let code = parsed.values["ErrorCode"] ?? ""
            guard code == "1019" else {
                throw IntegrationError.http(
                    status: Int(code) ?? 0,
                    body: parsed.values["ErrorMessage"] ?? "Unexpected Flex response"
                )
            }
            guard attempt < maxRetries else {
                throw IntegrationError.http(status: 1019, body: "Flex statement is still being generated; try again shortly")
            }
            attempt += 1
            if retryDelaySeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(retryDelaySeconds * 1_000_000_000))
            }
        }
    }

    // MARK: Parsing (public for tests / offline use)

    /// Parses a `FlexQueryResponse` XML document into executions.
    public static func executions(fromStatementXML data: Data, since: Date?) throws -> [ImportedExecution] {
        try executions(fromParsed: try FlexXMLParser.parse(data), since: since)
    }

    static func executions(fromParsed parsed: FlexXMLParser, since: Date?) throws -> [ImportedExecution] {
        var result: [ImportedExecution] = []
        for attrs in parsed.trades {
            guard let execution = try parseTrade(attrs) else { continue }
            if let since = since, execution.date < since { continue }
            result.append(execution)
        }
        return uniqueSorted(result)
    }

    private static func parseTrade(_ attrs: [String: String]) throws -> ImportedExecution? {
        if let level = attrs["levelOfDetail"], !level.isEmpty, level.uppercased() != "EXECUTION" { return nil }

        let assetClass: AssetClass
        switch (attrs["assetCategory"] ?? "").uppercased() {
        case "STK": assetClass = .usStock
        case "CRYPTO": assetClass = .cryptoSpot
        default: return nil
        }
        guard let rawSymbol = attrs["symbol"], !rawSymbol.isEmpty else { return nil }
        guard let externalID = attrs["tradeID"] ?? attrs["transactionID"], !externalID.isEmpty else { return nil }
        guard let date = parseDate(attrs) else {
            throw IntegrationError.decoding("Trade \(externalID): unreadable date")
        }
        guard let rawQuantity = IntegrationParsing.decimalOrNil(attrs["quantity"]), rawQuantity != 0 else { return nil }
        let price = try IntegrationParsing.decimal(attrs["tradePrice"] ?? "", field: "tradePrice")

        let side: ExecutionSide
        let buySell = (attrs["buySell"] ?? "").uppercased()
        if buySell.hasPrefix("BUY") {
            side = .buy
        } else if buySell.hasPrefix("SELL") {
            side = .sell
        } else {
            side = rawQuantity < 0 ? .sell : .buy
        }

        let currency = (attrs["currency"] ?? "USD").uppercased()
        var symbol = rawSymbol
        if assetClass == .cryptoSpot {
            symbol = rawSymbol.filter { $0.isLetter || $0.isNumber }.uppercased()
            if !symbol.hasSuffix(currency) { symbol += currency }
        }
        let fee = abs(IntegrationParsing.decimalOrNil(attrs["ibCommission"]) ?? 0)
        let feeCurrency = attrs["ibCommissionCurrency"].flatMap { $0.isEmpty ? nil : $0 } ?? currency

        return ImportedExecution(
            source: connectorID,
            externalID: externalID,
            orderID: attrs["ibOrderID"] ?? attrs["orderID"],
            symbol: symbol,
            assetClass: assetClass,
            side: side,
            quantity: abs(rawQuantity),
            price: price,
            fee: fee,
            feeCurrency: feeCurrency,
            date: date
        )
    }

    private static func parseDate(_ attrs: [String: String]) -> Date? {
        func digits(_ s: String?) -> String { (s ?? "").filter { $0.isNumber } }
        var combined = digits(attrs["dateTime"])
        if combined.count < 8 {
            let time = digits(attrs["tradeTime"])
            combined = digits(attrs["tradeDate"]) + (time.isEmpty ? "" : String((time + "000000").prefix(6)))
        }
        guard combined.count >= 8 else { return nil }
        let chars = Array(combined)
        func number(_ range: Range<Int>) -> Int {
            guard range.upperBound <= chars.count else { return 0 }
            return Int(String(chars[range])) ?? 0
        }
        var components = DateComponents()
        components.year = number(0..<4)
        components.month = number(4..<6)
        components.day = number(6..<8)
        components.hour = number(8..<10)
        components.minute = number(10..<12)
        components.second = number(12..<14)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -18000) ?? TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}

/// Minimal XML reader for Flex responses: remembers the root element name, the text of every leaf
/// element (last one wins) and the attributes of each `Trade` / `TradeConfirm` element.
final class FlexXMLParser: NSObject, XMLParserDelegate {
    private(set) var rootName: String?
    private(set) var values: [String: String] = [:]
    private(set) var trades: [[String: String]] = []
    private var buffer = ""

    static func parse(_ data: Data) throws -> FlexXMLParser {
        let handler = FlexXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        guard parser.parse() else {
            throw IntegrationError.decoding("Invalid XML: \(parser.parserError?.localizedDescription ?? "unknown error")")
        }
        return handler
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        if rootName == nil { rootName = elementName }
        buffer = ""
        if elementName == "Trade" || elementName == "TradeConfirm" {
            trades.append(attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { values[elementName] = text }
        buffer = ""
    }
}
