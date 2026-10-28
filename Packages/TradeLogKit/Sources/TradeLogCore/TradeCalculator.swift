import Foundation

public enum TradeCalculator {
    private static let breakevenTolerance = Decimal(string: "0.000001") ?? 0

    public static func metrics(for trade: TradeInput) -> TradeMetrics {
        let opens = trade.fills.filter { $0.action == .open }
        let closes = trade.fills.filter { $0.action == .close }

        let openedQty = opens.reduce(Decimal(0)) { $0 + $1.quantity }
        let closedQty = closes.reduce(Decimal(0)) { $0 + $1.quantity }

        var avgEntry: Decimal?
        if openedQty > 0 {
            let cost = opens.reduce(Decimal(0)) { $0 + $1.price * $1.quantity }
            avgEntry = cost / openedQty
        }
        var avgExit: Decimal?
        if closedQty > 0 {
            let proceeds = closes.reduce(Decimal(0)) { $0 + $1.price * $1.quantity }
            avgExit = proceeds / closedQty
        }

        var remaining = openedQty - closedQty
        if remaining < 0 { remaining = 0 }

        let entryForValue: Decimal = avgEntry ?? 0
        let positionValue = openedQty * entryForValue
        let leverage: Decimal = trade.leverage < 1 ? 1 : trade.leverage
        let marginUsed = positionValue / leverage

        let totalFees = trade.fills.reduce(Decimal(0)) { $0 + $1.fee }

        var gross = Decimal(0)
        if let entry = avgEntry, let exit = avgExit, closedQty > 0 {
            gross = (exit - entry) * closedQty * trade.side.sign
        }
        let net = gross - totalFees - trade.fundingFees

        let isFullyClosed = closedQty > 0 && remaining == 0

        // Planned risk / reward.
        let plannedEntryPrice: Decimal? = trade.plannedEntry ?? avgEntry
        var plannedRisk: Decimal?
        var rewardRatio: Decimal?
        if let entry = plannedEntryPrice, let stop = trade.stopLoss {
            let distance = absValue(entry - stop)
            plannedRisk = distance * openedQty
            if let tp = trade.takeProfit, distance > 0 {
                rewardRatio = absValue(tp - entry) / distance
            }
        }

        var rMultiple: Decimal?
        if isFullyClosed, let risk = plannedRisk, risk > 0 {
            rMultiple = net / risk
        }
        var returnOnMargin: Decimal?
        if isFullyClosed, marginUsed > 0 {
            returnOnMargin = net / marginUsed
        }

        var outcome: TradeOutcome = .open
        if isFullyClosed {
            if absValue(net) <= breakevenTolerance {
                outcome = .breakeven
            } else if net > 0 {
                outcome = .win
            } else {
                outcome = .loss
            }
        }

        let openDate = trade.fills.map { $0.date }.min()
        var closeDate: Date?
        if isFullyClosed {
            closeDate = closes.map { $0.date }.max()
        }
        var holding: TimeInterval?
        if let o = openDate, let c = closeDate {
            holding = c.timeIntervalSince(o)
        }

        return TradeMetrics(
            avgEntryPrice: avgEntry,
            avgExitPrice: avgExit,
            openedQuantity: openedQty,
            closedQuantity: closedQty,
            remainingQuantity: remaining,
            positionValue: positionValue,
            marginUsed: marginUsed,
            totalFees: totalFees,
            grossRealizedPnL: gross,
            netRealizedPnL: net,
            plannedRisk: plannedRisk,
            plannedRewardRatio: rewardRatio,
            rMultiple: rMultiple,
            returnOnMargin: returnOnMargin,
            outcome: outcome,
            openDate: openDate,
            closeDate: closeDate,
            holdingSeconds: holding
        )
    }

    /// Unrealized P&L on the remaining quantity, before fees.
    public static func unrealizedPnL(for trade: TradeInput, metrics: TradeMetrics, currentPrice: Decimal) -> Decimal {
        guard metrics.remainingQuantity > 0, let entry = metrics.avgEntryPrice else { return 0 }
        return (currentPrice - entry) * metrics.remainingQuantity * trade.side.sign
    }

    private static func absValue(_ value: Decimal) -> Decimal {
        return value < 0 ? -value : value
    }
}
