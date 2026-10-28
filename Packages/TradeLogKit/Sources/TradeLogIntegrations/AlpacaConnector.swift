import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradeLogCore

/// Alpaca trading API fill activities (`/v2/account/activities/FILL`). Read-only.
///
/// Assumptions / notes:
/// - `environment` credential is "live" or "paper" (anything else is treated as live).
/// - Pagination: ascending order, `page_size` rows per page, next page via `page_token` = last
///   activity id; stops when a page has fewer rows than `page_size`.
/// - Fee is 0: Alpaca is commission-free for stocks and reports regulatory / crypto fees as separate
///   non-FILL activities (FEE / CFEE), which are not imported here.
/// - Crypto symbols come as "BTC/USD" and are normalised to "BTCUSD" (`.cryptoSpot`).
/// - `transaction_time` is parsed with or without fractional seconds.
public struct AlpacaConnector: BrokerConnector {
    public static let connectorID = "alpaca"
    public static let displayName = "Alpaca"
    public static let credentialFields: [CredentialField] = [
        CredentialField(key: "keyID", label: "API Key ID", isSecret: true),
        CredentialField(key: "secretKey", label: "Secret Key", isSecret: true),
        CredentialField(key: "environment", label: "Environment (live or paper)", isSecret: false),
    ]

    private let credentials: [String: String]
    private let http: HTTPClient
    private let pageSize: Int

    public init(credentials: [String: String], session: HTTPClient) {
        self.init(credentials: credentials, session: session, pageSize: 100)
    }

    /// `pageSize` is exposed for tests (Alpaca allows up to 100 for this endpoint).
    public init(credentials: [String: String], session: HTTPClient, pageSize: Int) {
        self.credentials = credentials
        self.http = session
        self.pageSize = max(1, pageSize)
    }

    private struct Activity: Decodable {
        let id: String
        let symbol: String
        let side: String
        let qty: String
        let price: String
        let transaction_time: String
        let order_id: String?
    }

    var baseURL: String {
        (credentials["environment"] ?? "live").lowercased() == "paper"
            ? "https://paper-api.alpaca.markets"
            : "https://api.alpaca.markets"
    }

    public func fetchExecutions(since: Date?) async throws -> [ImportedExecution] {
        guard let keyID = credentials["keyID"]?.trimmingCharacters(in: .whitespaces), !keyID.isEmpty else {
            throw IntegrationError.missingCredential("keyID")
        }
        guard let secret = credentials["secretKey"]?.trimmingCharacters(in: .whitespaces), !secret.isEmpty else {
            throw IntegrationError.missingCredential("secretKey")
        }
        var result: [ImportedExecution] = []
        var pageToken: String?
        var pages = 0
        while pages < 1000 {
            pages += 1
            var params: [(String, String)] = []
            if let since = since { params.append(("after", DateParsing.iso8601String(since))) }
            params.append(("direction", "asc"))
            params.append(("page_size", String(pageSize)))
            if let token = pageToken { params.append(("page_token", token)) }
            let request = try RequestFactory.get(
                "\(baseURL)/v2/account/activities/FILL?\(QueryString.build(params))",
                headers: ["APCA-API-KEY-ID": keyID, "APCA-API-SECRET-KEY": secret]
            )
            let activities = try await http.sendJSON(request, as: [Activity].self)
            for activity in activities {
                if let execution = try map(activity) { result.append(execution) }
            }
            guard activities.count >= pageSize, let last = activities.last else { break }
            if last.id == pageToken { break } // defensive: no progress
            pageToken = last.id
        }
        return uniqueSorted(result)
    }

    private func map(_ activity: Activity) throws -> ImportedExecution? {
        let sideText = activity.side.lowercased()
        let side: ExecutionSide
        if sideText.contains("buy") {
            side = .buy
        } else if sideText.contains("sell") {
            side = .sell // includes "sell_short"
        } else {
            return nil
        }
        guard let date = DateParsing.iso8601(activity.transaction_time) else {
            throw IntegrationError.decoding("Invalid transaction_time '\(activity.transaction_time)'")
        }
        let isCrypto = activity.symbol.contains("/")
        let symbol = isCrypto ? activity.symbol.replacingOccurrences(of: "/", with: "") : activity.symbol
        return ImportedExecution(
            source: Self.connectorID,
            externalID: activity.id,
            orderID: activity.order_id,
            symbol: symbol,
            assetClass: isCrypto ? .cryptoSpot : .usStock,
            side: side,
            quantity: try IntegrationParsing.decimal(activity.qty, field: "qty"),
            price: try IntegrationParsing.decimal(activity.price, field: "price"),
            fee: 0,
            feeCurrency: "USD",
            date: date
        )
    }
}
