import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Shared value types used by the app, the calculators and the integrations.
// Pure Foundation only: this module must build on Linux and Apple platforms.
// All money values are Decimal. Prices/fees are in the trade's quote currency (USD or USDT,
// treated as USD) unless a field name says MYR.

public enum AssetClass: String, Codable, CaseIterable, Sendable, Hashable {
    case usStock
    case cryptoSpot
    case cryptoPerp // perpetual futures / derivatives, P&L-settled

    public var displayName: String {
        switch self {
        case .usStock: return "US Stock"
        case .cryptoSpot: return "Crypto Spot"
        case .cryptoPerp: return "Crypto Perp"
        }
    }
}

public enum TradeSide: String, Codable, CaseIterable, Sendable, Hashable {
    case long
    case short

    /// +1 for long, -1 for short.
    public var sign: Decimal { self == .long ? 1 : -1 }
}

/// Whether a fill increases (open) or reduces (close) the trade's position.
public enum FillAction: String, Codable, CaseIterable, Sendable, Hashable {
    case open
    case close
}

public enum TradeOutcome: String, Codable, CaseIterable, Sendable, Hashable {
    case open
    case win
    case loss
    case breakeven
}

public struct FillInput: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var action: FillAction
    public var date: Date
    public var price: Decimal
    public var quantity: Decimal // always positive
    public var fee: Decimal // in quote currency, always positive

    public init(id: UUID = UUID(), action: FillAction, date: Date, price: Decimal, quantity: Decimal, fee: Decimal = 0) {
        self.id = id
        self.action = action
        self.date = date
        self.price = price
        self.quantity = quantity
        self.fee = fee
    }
}

/// Plain snapshot of a trade, built by the app from its SwiftData model.
public struct TradeInput: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var symbol: String
    public var assetClass: AssetClass
    public var side: TradeSide
    public var leverage: Decimal // 1 for unleveraged
    public var plannedEntry: Decimal?
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var fills: [FillInput]
    public var fundingFees: Decimal // net funding paid (+) or received (-), quote currency
    public var setup: String?
    public var tags: [String] // indicators / free tags
    public var emotion: String?
    public var followedPlan: Bool?

    public init(
        id: UUID = UUID(), symbol: String, assetClass: AssetClass, side: TradeSide, leverage: Decimal = 1,
        plannedEntry: Decimal? = nil, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil,
        fills: [FillInput], fundingFees: Decimal = 0, setup: String? = nil, tags: [String] = [],
        emotion: String? = nil, followedPlan: Bool? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.assetClass = assetClass
        self.side = side
        self.leverage = leverage
        self.plannedEntry = plannedEntry
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.fills = fills
        self.fundingFees = fundingFees
        self.setup = setup
        self.tags = tags
        self.emotion = emotion
        self.followedPlan = followedPlan
    }
}

public struct TradeMetrics: Codable, Sendable, Hashable {
    public var avgEntryPrice: Decimal?
    public var avgExitPrice: Decimal?
    public var openedQuantity: Decimal
    public var closedQuantity: Decimal
    public var remainingQuantity: Decimal
    public var positionValue: Decimal // openedQuantity * avgEntryPrice
    public var marginUsed: Decimal // positionValue / leverage
    public var totalFees: Decimal
    public var grossRealizedPnL: Decimal // before fees and funding
    public var netRealizedPnL: Decimal // after fees and funding
    public var plannedRisk: Decimal? // |entry - stop| * openedQuantity
    public var plannedRewardRatio: Decimal? // |tp - entry| / |entry - stop|
    public var rMultiple: Decimal? // netRealizedPnL / plannedRisk
    public var returnOnMargin: Decimal? // netRealizedPnL / marginUsed
    public var outcome: TradeOutcome
    public var openDate: Date?
    public var closeDate: Date? // date of the last close fill when fully closed
    public var holdingSeconds: TimeInterval?

    public init(
        avgEntryPrice: Decimal?, avgExitPrice: Decimal?, openedQuantity: Decimal, closedQuantity: Decimal,
        remainingQuantity: Decimal, positionValue: Decimal, marginUsed: Decimal, totalFees: Decimal,
        grossRealizedPnL: Decimal, netRealizedPnL: Decimal, plannedRisk: Decimal?, plannedRewardRatio: Decimal?,
        rMultiple: Decimal?, returnOnMargin: Decimal?, outcome: TradeOutcome, openDate: Date?, closeDate: Date?,
        holdingSeconds: TimeInterval?
    ) {
        self.avgEntryPrice = avgEntryPrice
        self.avgExitPrice = avgExitPrice
        self.openedQuantity = openedQuantity
        self.closedQuantity = closedQuantity
        self.remainingQuantity = remainingQuantity
        self.positionValue = positionValue
        self.marginUsed = marginUsed
        self.totalFees = totalFees
        self.grossRealizedPnL = grossRealizedPnL
        self.netRealizedPnL = netRealizedPnL
        self.plannedRisk = plannedRisk
        self.plannedRewardRatio = plannedRewardRatio
        self.rMultiple = rMultiple
        self.returnOnMargin = returnOnMargin
        self.outcome = outcome
        self.openDate = openDate
        self.closeDate = closeDate
        self.holdingSeconds = holdingSeconds
    }
}

// MARK: - Integration contracts (implemented in TradeLogIntegrations)

public enum ExecutionSide: String, Codable, Sendable, Hashable {
    case buy
    case sell
}

/// One execution pulled from a broker/exchange API or a CSV file.
public struct ImportedExecution: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(source):\(externalID)" }
    public var source: String // connector id, e.g. "binance", "alpaca"
    public var externalID: String // unique within source; used to de-duplicate imports
    public var orderID: String?
    public var symbol: String // normalised: "AAPL", "BTCUSDT"
    public var assetClass: AssetClass
    public var side: ExecutionSide
    public var quantity: Decimal
    public var price: Decimal
    public var fee: Decimal
    public var feeCurrency: String?
    public var date: Date
    /// For derivatives: realised P&L reported by the exchange for this execution, if any.
    public var reportedRealizedPnL: Decimal?

    public init(
        source: String, externalID: String, orderID: String? = nil, symbol: String, assetClass: AssetClass,
        side: ExecutionSide, quantity: Decimal, price: Decimal, fee: Decimal = 0, feeCurrency: String? = nil,
        date: Date, reportedRealizedPnL: Decimal? = nil
    ) {
        self.source = source
        self.externalID = externalID
        self.orderID = orderID
        self.symbol = symbol
        self.assetClass = assetClass
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.feeCurrency = feeCurrency
        self.date = date
        self.reportedRealizedPnL = reportedRealizedPnL
    }
}

public struct Quote: Codable, Sendable, Hashable {
    public var symbol: String
    public var price: Decimal
    public var date: Date

    public init(symbol: String, price: Decimal, date: Date) {
        self.symbol = symbol
        self.price = price
        self.date = date
    }
}

/// Field names a connector needs (shown as a form in the app, values stored in the Keychain).
public struct CredentialField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var isSecret: Bool

    public init(key: String, label: String, isSecret: Bool) {
        self.key = key
        self.label = label
        self.isSecret = isSecret
    }
}

public protocol BrokerConnector: Sendable {
    static var connectorID: String { get }
    static var displayName: String { get }
    static var credentialFields: [CredentialField] { get }
    init(credentials: [String: String], session: HTTPClient)
    /// Read-only: fetch executions on/after `since` (nil = as far back as the API allows).
    func fetchExecutions(since: Date?) async throws -> [ImportedExecution]
}

public protocol PriceProvider: Sendable {
    func quotes(for symbols: [String], assetClass: AssetClass) async throws -> [String: Quote]
}

public protocol FXRateProvider: Sendable {
    /// MYR per 1 USD on the given date (latest available rate on or before the date).
    func usdToMYR(on date: Date) async throws -> Decimal
}

/// Minimal HTTP abstraction so connectors can be tested with fixtures.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum IntegrationError: Error, Sendable, Equatable {
    case missingCredential(String)
    case http(status: Int, body: String)
    case decoding(String)
    case unsupported(String)
}
