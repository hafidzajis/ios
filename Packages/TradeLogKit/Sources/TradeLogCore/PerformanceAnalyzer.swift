import Foundation

public enum BreakdownDimension: String, CaseIterable, Codable, Sendable {
    case setup, tag, symbol, assetClass, weekday, hourOfDay, emotion, followedPlan
}

public struct BreakdownRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    public var trades: Int
    public var wins: Int
    public var losses: Int
    public var winRate: Double
    public var netPnL: Decimal
    public var averageR: Decimal?

    public init(key: String, trades: Int, wins: Int, losses: Int, winRate: Double, netPnL: Decimal, averageR: Decimal?) {
        self.key = key
        self.trades = trades
        self.wins = wins
        self.losses = losses
        self.winRate = winRate
        self.netPnL = netPnL
        self.averageR = averageR
    }
}

public struct EquityPoint: Codable, Sendable, Hashable {
    public var date: Date
    public var cumulativePnL: Decimal

    public init(date: Date, cumulativePnL: Decimal) {
        self.date = date
        self.cumulativePnL = cumulativePnL
    }
}

public struct DailyPnL: Codable, Sendable, Hashable {
    public var day: Date // start of day in the calendar given to the analyzer
    public var pnl: Decimal
    public var tradeCount: Int

    public init(day: Date, pnl: Decimal, tradeCount: Int) {
        self.day = day
        self.pnl = pnl
        self.tradeCount = tradeCount
    }
}

public struct PerformanceReport: Codable, Sendable {
    public var totalClosedTrades: Int
    public var openTrades: Int
    public var wins: Int
    public var losses: Int
    public var breakevens: Int
    public var winRate: Double
    public var grossProfit: Decimal
    public var grossLoss: Decimal
    public var netPnL: Decimal
    public var totalFees: Decimal
    public var profitFactor: Double?
    public var expectancy: Decimal
    public var averageWin: Decimal
    public var averageLoss: Decimal
    public var largestWin: Decimal
    public var largestLoss: Decimal
    public var averageR: Decimal?
    public var averageHoldingSeconds: Double?
    public var maxDrawdown: Decimal
    public var maxDrawdownPercentOfPeak: Double?
    public var maxConsecutiveWins: Int
    public var maxConsecutiveLosses: Int
    public var equityCurve: [EquityPoint]
    public var dailyPnL: [DailyPnL]
    public var breakdowns: [BreakdownDimension: [BreakdownRow]]

    public init(
        totalClosedTrades: Int, openTrades: Int, wins: Int, losses: Int, breakevens: Int, winRate: Double,
        grossProfit: Decimal, grossLoss: Decimal, netPnL: Decimal, totalFees: Decimal, profitFactor: Double?,
        expectancy: Decimal, averageWin: Decimal, averageLoss: Decimal, largestWin: Decimal, largestLoss: Decimal,
        averageR: Decimal?, averageHoldingSeconds: Double?, maxDrawdown: Decimal, maxDrawdownPercentOfPeak: Double?,
        maxConsecutiveWins: Int, maxConsecutiveLosses: Int, equityCurve: [EquityPoint], dailyPnL: [DailyPnL],
        breakdowns: [BreakdownDimension: [BreakdownRow]]
    ) {
        self.totalClosedTrades = totalClosedTrades
        self.openTrades = openTrades
        self.wins = wins
        self.losses = losses
        self.breakevens = breakevens
        self.winRate = winRate
        self.grossProfit = grossProfit
        self.grossLoss = grossLoss
        self.netPnL = netPnL
        self.totalFees = totalFees
        self.profitFactor = profitFactor
        self.expectancy = expectancy
        self.averageWin = averageWin
        self.averageLoss = averageLoss
        self.largestWin = largestWin
        self.largestLoss = largestLoss
        self.averageR = averageR
        self.averageHoldingSeconds = averageHoldingSeconds
        self.maxDrawdown = maxDrawdown
        self.maxDrawdownPercentOfPeak = maxDrawdownPercentOfPeak
        self.maxConsecutiveWins = maxConsecutiveWins
        self.maxConsecutiveLosses = maxConsecutiveLosses
        self.equityCurve = equityCurve
        self.dailyPnL = dailyPnL
        self.breakdowns = breakdowns
    }

    public static let empty = PerformanceReport(
        totalClosedTrades: 0, openTrades: 0, wins: 0, losses: 0, breakevens: 0, winRate: 0,
        grossProfit: 0, grossLoss: 0, netPnL: 0, totalFees: 0, profitFactor: nil,
        expectancy: 0, averageWin: 0, averageLoss: 0, largestWin: 0, largestLoss: 0,
        averageR: nil, averageHoldingSeconds: nil, maxDrawdown: 0, maxDrawdownPercentOfPeak: nil,
        maxConsecutiveWins: 0, maxConsecutiveLosses: 0, equityCurve: [], dailyPnL: [], breakdowns: [:]
    )
}

public enum PerformanceAnalyzer {
    private struct Item {
        var trade: TradeInput
        var metrics: TradeMetrics
        var closeDate: Date
    }

    private struct Accumulator {
        var trades = 0
        var wins = 0
        var losses = 0
        var net = Decimal(0)
        var rSum = Decimal(0)
        var rCount = 0
    }

    public static func analyze(_ trades: [TradeInput], calendar: Calendar = .current) -> PerformanceReport {
        var items: [Item] = []
        var openCount = 0
        for trade in trades {
            let m = TradeCalculator.metrics(for: trade)
            if m.outcome == .open {
                openCount += 1
                continue
            }
            guard let closeDate = m.closeDate else {
                openCount += 1
                continue
            }
            items.append(Item(trade: trade, metrics: m, closeDate: closeDate))
        }
        items.sort { $0.closeDate < $1.closeDate }

        var wins = 0
        var losses = 0
        var breakevens = 0
        var grossProfit = Decimal(0)
        var grossLoss = Decimal(0)
        var net = Decimal(0)
        var fees = Decimal(0)
        var largestWin = Decimal(0)
        var largestLoss = Decimal(0)
        var rSum = Decimal(0)
        var rCount = 0
        var holdSum = 0.0
        var holdCount = 0

        var cumulative = Decimal(0)
        var peak = Decimal(0)
        var maxDD = Decimal(0)
        var maxDDPeak = Decimal(0)
        var curve: [EquityPoint] = []

        var winStreak = 0
        var lossStreak = 0
        var maxWinStreak = 0
        var maxLossStreak = 0

        var dailyMap: [Date: (pnl: Decimal, count: Int)] = [:]

        for item in items {
            let pnl = item.metrics.netRealizedPnL
            net += pnl
            fees += item.metrics.totalFees
            switch item.metrics.outcome {
            case .win:
                wins += 1
                grossProfit += pnl
                if pnl > largestWin { largestWin = pnl }
                winStreak += 1
                lossStreak = 0
                if winStreak > maxWinStreak { maxWinStreak = winStreak }
            case .loss:
                losses += 1
                let loss = -pnl
                grossLoss += loss
                if loss > largestLoss { largestLoss = loss }
                lossStreak += 1
                winStreak = 0
                if lossStreak > maxLossStreak { maxLossStreak = lossStreak }
            case .breakeven, .open:
                breakevens += 1
                winStreak = 0
                lossStreak = 0
            }
            if let r = item.metrics.rMultiple {
                rSum += r
                rCount += 1
            }
            if let h = item.metrics.holdingSeconds {
                holdSum += h
                holdCount += 1
            }

            cumulative += pnl
            curve.append(EquityPoint(date: item.closeDate, cumulativePnL: cumulative))
            if cumulative > peak { peak = cumulative }
            let drawdown = peak - cumulative
            if drawdown > maxDD {
                maxDD = drawdown
                maxDDPeak = peak
            }

            let day = calendar.startOfDay(for: item.closeDate)
            let existing = dailyMap[day] ?? (pnl: Decimal(0), count: 0)
            dailyMap[day] = (pnl: existing.pnl + pnl, count: existing.count + 1)
        }

        let closed = items.count
        let decided = wins + losses
        let winRate = decided > 0 ? Double(wins) / Double(decided) : 0
        var profitFactor: Double?
        if grossLoss > 0 {
            profitFactor = (grossProfit / grossLoss).doubleValue
        }
        let expectancy: Decimal = closed > 0 ? net / Decimal(closed) : 0
        let averageWin: Decimal = wins > 0 ? grossProfit / Decimal(wins) : 0
        let averageLoss: Decimal = losses > 0 ? grossLoss / Decimal(losses) : 0
        let averageR: Decimal? = rCount > 0 ? rSum / Decimal(rCount) : nil
        let averageHolding: Double? = holdCount > 0 ? holdSum / Double(holdCount) : nil
        var ddPercent: Double?
        if maxDD > 0 && maxDDPeak > 0 {
            ddPercent = (maxDD / maxDDPeak).doubleValue
        }

        let daily = dailyMap.keys.sorted().map { day -> DailyPnL in
            let entry = dailyMap[day] ?? (pnl: Decimal(0), count: 0)
            return DailyPnL(day: day, pnl: entry.pnl, tradeCount: entry.count)
        }

        var breakdowns: [BreakdownDimension: [BreakdownRow]] = [:]
        for dimension in BreakdownDimension.allCases {
            breakdowns[dimension] = breakdown(items: items, dimension: dimension, calendar: calendar)
        }

        return PerformanceReport(
            totalClosedTrades: closed, openTrades: openCount, wins: wins, losses: losses, breakevens: breakevens,
            winRate: winRate, grossProfit: grossProfit, grossLoss: grossLoss, netPnL: net, totalFees: fees,
            profitFactor: profitFactor, expectancy: expectancy, averageWin: averageWin, averageLoss: averageLoss,
            largestWin: largestWin, largestLoss: largestLoss, averageR: averageR,
            averageHoldingSeconds: averageHolding, maxDrawdown: maxDD, maxDrawdownPercentOfPeak: ddPercent,
            maxConsecutiveWins: maxWinStreak, maxConsecutiveLosses: maxLossStreak,
            equityCurve: curve, dailyPnL: daily, breakdowns: breakdowns
        )
    }

    private static func keys(for item: Item, dimension: BreakdownDimension, calendar: Calendar) -> [String] {
        let trade = item.trade
        switch dimension {
        case .setup:
            if let s = trade.setup, !s.isEmpty { return [s] }
            return ["No setup"]
        case .tag:
            var seen = Set<String>()
            var result: [String] = []
            for tag in trade.tags where !tag.isEmpty {
                if seen.insert(tag).inserted { result.append(tag) }
            }
            return result.isEmpty ? ["Untagged"] : result
        case .symbol:
            return [trade.symbol]
        case .assetClass:
            return [trade.assetClass.displayName]
        case .weekday:
            let index = calendar.component(.weekday, from: item.closeDate) - 1
            let symbols = calendar.weekdaySymbols
            if index >= 0 && index < symbols.count { return [symbols[index]] }
            return ["Unknown"]
        case .hourOfDay:
            let date = item.metrics.openDate ?? item.closeDate
            let hour = calendar.component(.hour, from: date)
            return [hour < 10 ? "0\(hour):00" : "\(hour):00"]
        case .emotion:
            if let e = trade.emotion, !e.isEmpty { return [e] }
            return ["\u{2014}"]
        case .followedPlan:
            if let f = trade.followedPlan { return [f ? "Followed plan" : "Broke plan"] }
            return ["Not recorded"]
        }
    }

    private static func breakdown(items: [Item], dimension: BreakdownDimension, calendar: Calendar) -> [BreakdownRow] {
        var map: [String: Accumulator] = [:]
        for item in items {
            for key in keys(for: item, dimension: dimension, calendar: calendar) {
                var acc = map[key] ?? Accumulator()
                acc.trades += 1
                acc.net += item.metrics.netRealizedPnL
                if item.metrics.outcome == .win { acc.wins += 1 }
                if item.metrics.outcome == .loss { acc.losses += 1 }
                if let r = item.metrics.rMultiple {
                    acc.rSum += r
                    acc.rCount += 1
                }
                map[key] = acc
            }
        }
        var rows: [BreakdownRow] = []
        for (key, acc) in map {
            let decided = acc.wins + acc.losses
            let rate = decided > 0 ? Double(acc.wins) / Double(decided) : 0
            let avgR: Decimal? = acc.rCount > 0 ? acc.rSum / Decimal(acc.rCount) : nil
            rows.append(BreakdownRow(key: key, trades: acc.trades, wins: acc.wins, losses: acc.losses,
                                     winRate: rate, netPnL: acc.net, averageR: avgR))
        }
        rows.sort { a, b in
            if a.netPnL != b.netPnL { return a.netPnL > b.netPnL }
            return a.key < b.key
        }
        return rows
    }
}
