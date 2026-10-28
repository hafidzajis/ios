import Foundation
import SwiftData
import TradeLogCore

struct FillDraft: Identifiable {
    var id = UUID()
    var action: FillAction = .open
    var date = Date()
    var price: Decimal?
    var quantity: Decimal?
    var fee: Decimal?
    var externalID: String?
}

struct AttachmentDraft: Identifiable {
    var id = UUID()
    var data: Data
    var caption = ""
}

/// Editable copy of a Trade. The editor works on this so Cancel discards everything.
struct TradeDraft {
    var account: Account?
    var symbol = ""
    var assetClass: AssetClass = .usStock
    var side: TradeSide = .long
    var leverage: Decimal? = 1
    var plannedEntry: Decimal?
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var fundingFees: Decimal?
    var setup: Setup?
    var tagIDs: Set<UUID> = []
    var timeframe = ""
    var emotion: Emotion?
    var followedPlan: Bool?
    var notes = ""
    var fills: [FillDraft] = [FillDraft()]
    var attachments: [AttachmentDraft] = []

    init() {}

    init(trade: Trade) {
        account = trade.account
        symbol = trade.symbol
        assetClass = trade.assetClass
        side = trade.side
        leverage = trade.leverage
        plannedEntry = trade.plannedEntry
        stopLoss = trade.stopLoss
        takeProfit = trade.takeProfit
        fundingFees = trade.fundingFees == 0 ? nil : trade.fundingFees
        setup = trade.setup
        tagIDs = Set((trade.tags ?? []).map(\.uuid))
        timeframe = trade.timeframe ?? ""
        emotion = trade.emotion.flatMap { Emotion(rawValue: $0) }
        followedPlan = trade.followedPlan
        notes = trade.notes
        fills = trade.sortedFills.map {
            FillDraft(id: $0.uuid, action: $0.action, date: $0.date, price: $0.price, quantity: $0.quantity, fee: $0.fee, externalID: $0.externalID)
        }
        attachments = trade.sortedAttachments.compactMap { a in
            a.imageData.map { AttachmentDraft(id: a.uuid, data: $0, caption: a.caption) }
        }
    }

    /// Plan, setup and tags of an existing trade with fresh fills; used by "Duplicate".
    static func duplicating(_ trade: Trade) -> TradeDraft {
        var d = TradeDraft(trade: trade)
        d.fills = [FillDraft()]
        d.attachments = []
        d.notes = ""
        d.emotion = nil
        d.followedPlan = nil
        return d
    }

    // MARK: Calculation

    func input() -> TradeInput {
        TradeInput(
            symbol: symbol,
            assetClass: assetClass,
            side: side,
            leverage: max(leverage ?? 1, 1),
            plannedEntry: plannedEntry,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            fills: fills.compactMap { f in
                guard let price = f.price, let qty = f.quantity, qty > 0 else { return nil }
                return FillInput(id: f.id, action: f.action, date: f.date, price: price, quantity: qty, fee: f.fee ?? 0)
            },
            fundingFees: assetClass == .cryptoPerp ? (fundingFees ?? 0) : 0
        )
    }

    // MARK: Validation

    var validationErrors: [String] {
        var errors: [String] = []
        if symbol.trimmingCharacters(in: .whitespaces).isEmpty { errors.append("Symbol is required.") }
        let valid = fills.filter { ($0.price ?? 0) > 0 && ($0.quantity ?? 0) > 0 }
        if valid.count != fills.count { errors.append("Every fill needs a price and quantity above zero.") }
        let opens = valid.filter { $0.action == .open }.reduce(Decimal(0)) { $0 + ($1.quantity ?? 0) }
        let closes = valid.filter { $0.action == .close }.reduce(Decimal(0)) { $0 + ($1.quantity ?? 0) }
        if opens == 0 { errors.append("Add at least one open fill.") }
        if closes > opens { errors.append("Closed quantity (\(Fmt.plain(closes))) exceeds opened quantity (\(Fmt.plain(opens))).") }
        return errors
    }

    // MARK: Apply

    @MainActor
    func apply(to trade: Trade, context: ModelContext, allTags: [Tag]) {
        trade.symbol = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        trade.assetClass = assetClass
        trade.side = side
        trade.leverage = max(leverage ?? 1, 1)
        trade.plannedEntry = plannedEntry
        trade.stopLoss = stopLoss
        trade.takeProfit = takeProfit
        trade.fundingFees = assetClass == .cryptoPerp ? (fundingFees ?? 0) : 0
        trade.account = account
        trade.setup = setup
        trade.tags = allTags.filter { tagIDs.contains($0.uuid) }
        trade.timeframe = timeframe.trimmingCharacters(in: .whitespaces).isEmpty ? nil : timeframe
        trade.emotion = emotion?.rawValue
        trade.followedPlan = followedPlan
        trade.notes = notes
        trade.updatedAt = Date()

        // Fills
        let draftIDs = Set(fills.map(\.id))
        for fill in trade.fills ?? [] where !draftIDs.contains(fill.uuid) {
            trade.fills?.removeAll { $0 === fill }
            context.delete(fill)
        }
        for draft in fills {
            guard let price = draft.price, let quantity = draft.quantity else { continue }
            if let existing = (trade.fills ?? []).first(where: { $0.uuid == draft.id }) {
                existing.action = draft.action
                existing.date = draft.date
                existing.price = price
                existing.quantity = quantity
                existing.fee = draft.fee ?? 0
            } else {
                let fill = Fill(uuid: draft.id, action: draft.action, date: draft.date, price: price, quantity: quantity,
                                fee: draft.fee ?? 0, externalID: draft.externalID)
                context.insert(fill)
                trade.addFill(fill)
            }
        }

        // Attachments
        let attachmentIDs = Set(attachments.map(\.id))
        for att in trade.attachments ?? [] where !attachmentIDs.contains(att.uuid) {
            trade.attachments?.removeAll { $0 === att }
            context.delete(att)
        }
        for draft in attachments {
            if let existing = (trade.attachments ?? []).first(where: { $0.uuid == draft.id }) {
                existing.caption = draft.caption
            } else {
                let att = Attachment(uuid: draft.id, imageData: draft.data, caption: draft.caption)
                context.insert(att)
                trade.addAttachment(att)
            }
        }

        trade.refreshCache()
    }
}
