import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradeLogCore

/// Bybit V5 executions (`/v5/execution/list`) for `spot` and `linear`. Read-only.
///
/// Assumptions / notes:
/// - Signature: HMAC_SHA256(timestamp + apiKey + recvWindow + queryString) as lower-case hex.
/// - startTime/endTime must span at most 7 days -> `since` is split in ~7-day windows (clamped to
///   the last 730 days, which is how long Bybit keeps executions). Without `since` a single request
///   without a time range is made (Bybit then returns the latest 7 days).
/// - Only `execType == "Trade"` rows are used (funding, ADL, bust rows are skipped).
/// - Linear fees are in USDT. Spot fees use the `feeCurrency` field when present.
/// - The executions endpoint does not carry realised P&L, so `reportedRealizedPnL` stays nil.
public struct BybitConnector: BrokerConnector {
    public static let connectorID = "bybit"
    public static let displayName = "Bybit"
    public static let credentialFields: [CredentialField] = [
        CredentialField(key: "apiKey", label: "API Key", isSecret: true),
        CredentialField(key: "apiSecret", label: "API Secret", isSecret: true),
    ]

    static let baseURL = "https://api.bybit.com"
    private static let recvWindow = "5000"
    private static let pageLimit = 100
    private static let maxPages = 500
    private static let windowSeconds: TimeInterval = 7 * 86400 - 60
    private static let historySeconds: TimeInterval = 730 * 86400

    private let credentials: [String: String]
    private let http: HTTPClient

    public init(credentials: [String: String], session: HTTPClient) {
        self.credentials = credentials
        self.http = session
    }

    private struct Response: Decodable {
        let retCode: Int
        let retMsg: String
        let result: ResultBody?
    }

    private struct ResultBody: Decodable {
        let list: [Execution]?
        let nextPageCursor: String?
    }

    private struct Execution: Decodable {
        let symbol: String
        let side: String
        let execQty: String
        let execPrice: String
        let execFee: String?
        let feeCurrency: String?
        let execId: String
        let orderId: String?
        let execTime: String
        let execType: String?
    }

    public func fetchExecutions(since: Date?) async throws -> [ImportedExecution] {
        guard let apiKey = credentials["apiKey"]?.trimmingCharacters(in: .whitespaces), !apiKey.isEmpty else {
            throw IntegrationError.missingCredential("apiKey")
        }
        guard let secret = credentials["apiSecret"]?.trimmingCharacters(in: .whitespaces), !secret.isEmpty else {
            throw IntegrationError.missingCredential("apiSecret")
        }
        var all: [ImportedExecution] = []
        for category in ["spot", "linear"] {
            all += try await fetchCategory(category, since: since, apiKey: apiKey, secret: secret)
        }
        return uniqueSorted(all)
    }

    private func fetchCategory(_ category: String, since: Date?, apiKey: String, secret: String) async throws -> [ImportedExecution] {
        guard let since = since else {
            return try await fetchWindow(category, startMS: nil, endMS: nil, apiKey: apiKey, secret: secret)
        }
        let now = Date()
        var start = max(since, now.addingTimeInterval(-Self.historySeconds))
        var result: [ImportedExecution] = []
        while start < now {
            let end = min(start.addingTimeInterval(Self.windowSeconds), now)
            result += try await fetchWindow(
                category,
                startMS: IntegrationParsing.milliseconds(start),
                endMS: IntegrationParsing.milliseconds(end),
                apiKey: apiKey, secret: secret
            )
            start = end
        }
        return result
    }

    private func fetchWindow(_ category: String, startMS: Int64?, endMS: Int64?, apiKey: String, secret: String) async throws -> [ImportedExecution] {
        var result: [ImportedExecution] = []
        var cursor: String?
        var pages = 0
        while pages < Self.maxPages {
            pages += 1
            var params: [(String, String)] = [("category", category), ("limit", String(Self.pageLimit))]
            if let s = startMS { params.append(("startTime", String(s))) }
            if let e = endMS { params.append(("endTime", String(e))) }
            if let c = cursor, !c.isEmpty { params.append(("cursor", c)) }
            let request = try signedRequest(params: params, apiKey: apiKey, secret: secret)
            let response = try await http.sendJSON(request, as: Response.self)
            guard response.retCode == 0 else {
                throw IntegrationError.http(status: response.retCode, body: response.retMsg)
            }
            for item in response.result?.list ?? [] {
                if let type = item.execType, type != "Trade" { continue }
                guard let execution = try map(item, category: category) else { continue }
                result.append(execution)
            }
            guard let next = response.result?.nextPageCursor, !next.isEmpty else { break }
            cursor = next
        }
        return result
    }

    func signedRequest(params: [(String, String)], apiKey: String, secret: String) throws -> URLRequest {
        let query = QueryString.build(params)
        let timestamp = String(IntegrationParsing.milliseconds(Date()))
        let signature = HMACSigner.sha256Hex(message: timestamp + apiKey + Self.recvWindow + query, secret: secret)
        return try RequestFactory.get(
            "\(Self.baseURL)/v5/execution/list?\(query)",
            headers: [
                "X-BAPI-API-KEY": apiKey,
                "X-BAPI-SIGN": signature,
                "X-BAPI-TIMESTAMP": timestamp,
                "X-BAPI-RECV-WINDOW": Self.recvWindow,
            ]
        )
    }

    private func map(_ item: Execution, category: String) throws -> ImportedExecution? {
        let side: ExecutionSide
        switch item.side.lowercased() {
        case "buy": side = .buy
        case "sell": side = .sell
        default: return nil
        }
        guard let ms = Int64(item.execTime) else {
            throw IntegrationError.decoding("Invalid execTime '\(item.execTime)'")
        }
        let isLinear = category == "linear"
        var feeCurrency = item.feeCurrency
        if isLinear { feeCurrency = "USDT" }
        if let fc = feeCurrency, fc.isEmpty { feeCurrency = nil }
        return ImportedExecution(
            source: Self.connectorID,
            externalID: item.execId,
            orderID: item.orderId,
            symbol: item.symbol,
            assetClass: isLinear ? .cryptoPerp : .cryptoSpot,
            side: side,
            quantity: try IntegrationParsing.decimal(item.execQty, field: "execQty"),
            price: try IntegrationParsing.decimal(item.execPrice, field: "execPrice"),
            fee: IntegrationParsing.decimalOrNil(item.execFee) ?? 0,
            feeCurrency: feeCurrency,
            date: IntegrationParsing.date(milliseconds: ms)
        )
    }
}
