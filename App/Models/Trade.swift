import Foundation
import SwiftData
import TradeLogCore

@Model
final class Trade {
    var uuid: UUID = UUID()
    var symbol: String = ""
    var assetClassRaw: String = AssetClass.usStock.rawValue
    var sideRaw: String = TradeSide.long.rawValue
    var leverage: Decimal = 1
    var plannedEntry: Decimal?
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var fundingFees: Decimal = 0
    var setup: Setup?
    @Relationship(inverse: \Tag.trades)
    var tags: [Tag]?
    var emotion: String?
    var followedPlan: Bool?
    var notes: String = ""
    var timeframe: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Fill.trade)
    var fills: [Fill]?
    @Relationship(deleteRule: .cascade, inverse: \Attachment.trade)
    var attachments: [Attachment]?

    // Cached values, refreshed by `refreshCache()`, for cheap sorting/filtering.
    var cachedNetPnL: Decimal = 0
    var cachedOutcomeRaw: String = TradeOutcome.open.rawValue
    var cachedOpenDate: Date?
    var cachedCloseDate: Date?
    var cachedRMultiple: Decimal?

    init(symbol: String, assetClass: AssetClass, side: TradeSide, account: Account? = nil) {
        self.uuid = UUID()
        self.symbol = symbol
        self.assetClassRaw = assetClass.rawValue
        self.sideRaw = side.rawValue
        self.account = account
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Typed accessors

    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .usStock }
        set { assetClassRaw = newValue.rawValue }
    }

    var side: TradeSide {
        get { TradeSide(rawValue: sideRaw) ?? .long }
        set { sideRaw = newValue.rawValue }
    }

    var outcome: TradeOutcome {
        TradeOutcome(rawValue: cachedOutcomeRaw) ?? .open
    }

    var isOpen: Bool { outcome == .open }

    var sortedFills: [Fill] {
        (fills ?? []).sorted { $0.date < $1.date }
    }

    var sortedAttachments: [Attachment] {
        (attachments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Date used for ordering and date-range filtering.
    var sortDate: Date {
        cachedCloseDate ?? cachedOpenDate ?? createdAt
    }

    func addFill(_ fill: Fill) {
        if fills == nil { fills = [fill] } else { fills?.append(fill) }
    }

    func addAttachment(_ attachment: Attachment) {
        if attachments == nil { attachments = [attachment] } else { attachments?.append(attachment) }
    }

    // MARK: Calculation bridge

    func snapshot() -> TradeInput {
        TradeInput(
            id: uuid,
            symbol: symbol,
            assetClass: assetClass,
            side: side,
            leverage: leverage,
            plannedEntry: plannedEntry,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            fills: sortedFills.map {
                FillInput(id: $0.uuid, action: $0.action, date: $0.date, price: $0.price, quantity: $0.quantity, fee: $0.fee)
            },
            fundingFees: fundingFees,
            setup: setup?.name,
            tags: (tags ?? []).map(\.name),
            emotion: emotion,
            followedPlan: followedPlan
        )
    }

    var metrics: TradeMetrics {
        TradeCalculator.metrics(for: snapshot())
    }

    func refreshCache() {
        let m = TradeCalculator.metrics(for: snapshot())
        cachedNetPnL = m.netRealizedPnL
        cachedOutcomeRaw = m.outcome.rawValue
        cachedOpenDate = m.openDate
        cachedCloseDate = m.closeDate
        cachedRMultiple = m.rMultiple
    }
}

extension Collection where Element == Trade {
    var snapshots: [TradeInput] { map { $0.snapshot() } }
}
