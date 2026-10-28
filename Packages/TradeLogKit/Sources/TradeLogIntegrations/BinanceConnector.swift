import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradeLogCore

/// Binance spot (`/api/v3/myTrades`) and USDⓈ-M futures (`/fapi/v1/userTrades`). Read-only.
///
/// Assumptions / notes:
/// - Binance requires a symbol per request, so the user lists symbols ("BTCUSDT,ETHUSDT").
/// - `externalID` is `"<SYMBOL>-<id>"` for spot and `"F-<SYMBOL>-<id>"` for futures, because trade
///   ids are only unique per symbol (and spot / futures id spaces overlap).
/// - Fees are reported in `commissionAsset` (e.g. BNB or the base coin); no conversion is done here.
/// - Futures `userTrades` only keeps ~6 months and each request spans at most 7 days, so a given
///   `since` is clamped to 180 days back and split in ~7-day windows.
public struct BinanceConnector: BrokerConnector {
    public static let connectorID = "binance"
    public static let displayName = "Binance"
    public static let credentialFields: [CredentialField] = [
        CredentialField(key: "apiKey", label: "API Key", isSecret: true),
        CredentialField(key: "apiSecret", label: "API Secret", isSecret: true),
        CredentialField(key: "symbols", label: "Symbols (comma separated, e.g. BTCUSDT,ETHUSDT)", isSecret: false),
        CredentialField(key: "includeFutures", label: "Include USDⓈ-M futures (true/false)", isSecret: false),
    ]

    static let spotBase = "https://api.binance.com"
    static let futuresBase = "https://fapi.binance.com"
    private static let pageLimit = 1000
    private static let maxPages = 500
    private static let windowSeconds: TimeInterval = 7 * 86400 - 60
    private static let futuresHistorySeconds: TimeInterval = 180 * 86400

    private let credentials: [String: String]
    private let http: HTTPClient

    public init(credentials: [String: String], session: HTTPClient) {
        self.credentials = credentials
        self.http = session
    }

    public func fetchExecutions(since: Date?) async throws -> [ImportedExecution] {
        guard let apiKey = credentials["apiKey"]?.trimmingCharacters(in: .whitespaces), !apiKey.isEmpty else {
            throw IntegrationError.missingCredential("apiKey")
        }
        guard let secret = credentials["apiSecret"]?.trimmingCharacters(in: .whitespaces), !secret.isEmpty else {
            throw IntegrationError.missingCredential("apiSecret")
        }
        let symbols = commaSeparatedSymbols(credentials["symbols"])
        guard !symbols.isEmpty else { throw IntegrationError.missingCredential("symbols") }
        let includeFutures = (credentials["includeFutures"] ?? "false").lowercased() == "true"

        var all: [ImportedExecution] = []
        for symbol in symbols {
            all += try await fetchSpot(symbol: symbol, since: since, apiKey: apiKey, secret: secret)
        }
        if includeFutures {
            for symbol in symbols {
                all += try await fetchFutures(symbol: symbol, since: since, apiKey: apiKey, secret: secret)
            }
        }
        return uniqueSorted(all)
    }

    // MARK: Signing

    /// Builds `base + path ? params & timestamp & recvWindow & signature` (HMAC over the query string).
    func signedRequest(base: String, path: String, params: [(String, String)], apiKey: String, secret: String) throws -> URLRequest {
        var items = params
        items.append(("timestamp", String(IntegrationParsing.milliseconds(Date()))))
        items.append(("recvWindow", "5000"))
        let query = QueryString.build(items)
        let signature = HMACSigner.sha256Hex(message: query, secret: secret)
        return try RequestFactory.get("\(base)\(path)?\(query)&signature=\(signature)", headers: ["X-MBX-APIKEY": apiKey])
    }

    // MARK: Spot

    private struct SpotTrade: Decodable {
        let id: Int64
        let orderId: Int64?
        let price: String
        let qty: String
        let commission: String
        let commissionAsset: String
        let time: Int64
        let isBuyer: Bool
    }

    private func fetchSpot(symbol: String, since: Date?, apiKey: String, secret: String) async throws -> [ImportedExecution] {
        var result: [ImportedExecution] = []
        var fromId: Int64?
        var pages = 0
        while pages < Self.maxPages {
            pages += 1
            var params: [(String, String)] = [("symbol", symbol)]
            if let fromId = fromId {
                params.append(("fromId", String(fromId))) // fromId cannot be combined with startTime
            } else if let since = since {
                params.append(("startTime", String(IntegrationParsing.milliseconds(since))))
            }
            params.append(("limit", String(Self.pageLimit)))
            let request = try signedRequest(base: Self.spotBase, path: "/api/v3/myTrades", params: params, apiKey: apiKey, secret: secret)
            let trades = try await http.sendJSON(request, as: [SpotTrade].self)
            for trade in trades {
                result.append(ImportedExecution(
                    source: Self.connectorID,
                    externalID: "\(symbol)-\(trade.id)",
                    orderID: trade.orderId.map { String($0) },
                    symbol: symbol,
                    assetClass: .cryptoSpot,
                    side: trade.isBuyer ? .buy : .sell,
                    quantity: try IntegrationParsing.decimal(trade.qty, field: "qty"),
                    price: try IntegrationParsing.decimal(trade.price, field: "price"),
                    fee: try IntegrationParsing.decimal(trade.commission, field: "commission"),
                    feeCurrency: trade.commissionAsset,
                    date: IntegrationParsing.date(milliseconds: trade.time)
                ))
            }
            guard trades.count >= Self.pageLimit, let last = trades.last else { break }
            fromId = last.id + 1
        }
        return result
    }

    // MARK: Futures

    private struct FuturesTrade: Decodable {
        let id: Int64
        let orderId: Int64?
        let side: String
        let price: String
        let qty: String
        let realizedPnl: String?
        let commission: String
        let commissionAsset: String
        let time: Int64
    }

    private func fetchFutures(symbol: String, since: Date?, apiKey: String, secret: String) async throws -> [ImportedExecution] {
        guard let since = since else {
            // No lower bound: Binance returns the latest trades (last 7 days window, max 1000).
            return try await futuresWindow(symbol: symbol, startMS: nil, endMS: nil, apiKey: apiKey, secret: secret)
        }
        let now = Date()
        var start = max(since, now.addingTimeInterval(-Self.futuresHistorySeconds))
        var result: [ImportedExecution] = []
        while start < now {
            let end = min(start.addingTimeInterval(Self.windowSeconds), now)
            result += try await futuresWindow(
                symbol: symbol,
                startMS: IntegrationParsing.milliseconds(start),
                endMS: IntegrationParsing.milliseconds(end),
                apiKey: apiKey, secret: secret
            )
            start = end
        }
        return result
    }

    private func futuresWindow(symbol: String, startMS: Int64?, endMS: Int64?, apiKey: String, secret: String) async throws -> [ImportedExecution] {
        var result: [ImportedExecution] = []
        var seen = Set<Int64>()
        var currentStart = startMS
        var pages = 0
        while pages < Self.maxPages {
            pages += 1
            var params: [(String, String)] = [("symbol", symbol)]
            if let s = currentStart { params.append(("startTime", String(s))) }
            if let e = endMS { params.append(("endTime", String(e))) }
            params.append(("limit", String(Self.pageLimit)))
            let request = try signedRequest(base: Self.futuresBase, path: "/fapi/v1/userTrades", params: params, apiKey: apiKey, secret: secret)
            let trades = try await http.sendJSON(request, as: [FuturesTrade].self)
            var added = 0
            for trade in trades where seen.insert(trade.id).inserted {
                added += 1
                let side: ExecutionSide = trade.side.uppercased() == "BUY" ? .buy : .sell
                result.append(ImportedExecution(
                    source: Self.connectorID,
                    externalID: "F-\(symbol)-\(trade.id)",
                    orderID: trade.orderId.map { String($0) },
                    symbol: symbol,
                    assetClass: .cryptoPerp,
                    side: side,
                    quantity: try IntegrationParsing.decimal(trade.qty, field: "qty"),
                    price: try IntegrationParsing.decimal(trade.price, field: "price"),
                    fee: try IntegrationParsing.decimal(trade.commission, field: "commission"),
                    feeCurrency: trade.commissionAsset,
                    date: IntegrationParsing.date(milliseconds: trade.time),
                    reportedRealizedPnL: IntegrationParsing.decimalOrNil(trade.realizedPnl)
                ))
            }
            // Only continue inside a time window when the page was full; advance startTime to the
            // last trade time (inclusive; duplicates are filtered by id).
            guard trades.count >= Self.pageLimit, added > 0, currentStart != nil, let last = trades.last else { break }
            currentStart = last.time
        }
        return result
    }
}
