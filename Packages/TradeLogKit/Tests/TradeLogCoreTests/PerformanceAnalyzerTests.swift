import XCTest
@testable import TradeLogCore

final class PerformanceAnalyzerTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return c
    }

    /// Closed long trade of qty 1 with the given net P&L, closing on `day` (1...28 of March 2024).
    private func trade(pnl: Int, day: Int, setup: String? = nil, tags: [String] = []) -> TradeInput {
        let dayString = day < 10 ? "0\(day)" : "\(day)"
        return TradeInput(
            symbol: "AAPL", assetClass: .usStock, side: .long,
            fills: [
                fill(.open, "2024-03-\(dayString)T09:00:00Z", "1000", "1"),
                fill(.close, "2024-03-\(dayString)T15:00:00Z", "\(1000 + pnl)", "1"),
            ],
            setup: setup, tags: tags
        )
    }

    func testEmpty() {
        let r = PerformanceAnalyzer.analyze([], calendar: utc)
        XCTAssertEqual(r.totalClosedTrades, 0)
        XCTAssertEqual(r.winRate, 0)
        XCTAssertNil(r.profitFactor)
        XCTAssertEqual(r.maxDrawdown, 0)
    }

    func testWinRateAndProfitFactor() {
        let trades = [trade(pnl: 100, day: 1), trade(pnl: -50, day: 2), trade(pnl: -80, day: 3), trade(pnl: 40, day: 4)]
        let r = PerformanceAnalyzer.analyze(trades, calendar: utc)
        XCTAssertEqual(r.totalClosedTrades, 4)
        XCTAssertEqual(r.wins, 2)
        XCTAssertEqual(r.losses, 2)
        XCTAssertEqual(r.winRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(r.grossProfit, 140)
        XCTAssertEqual(r.grossLoss, 130)
        XCTAssertEqual(r.netPnL, 10)
        XCTAssertEqual(r.profitFactor ?? 0, 140.0 / 130.0, accuracy: 0.0001)
        XCTAssertEqual(r.largestWin, 100)
        XCTAssertEqual(r.largestLoss, 80)
        XCTAssertEqual(r.averageWin, 70)
        XCTAssertEqual(r.averageLoss, 65)
        XCTAssertEqual(r.expectancy, d("2.5"))
    }

    func testDrawdownAndStreaks() {
        let trades = [trade(pnl: 100, day: 1), trade(pnl: -50, day: 2), trade(pnl: -80, day: 3), trade(pnl: 40, day: 4)]
        let r = PerformanceAnalyzer.analyze(trades, calendar: utc)
        XCTAssertEqual(r.maxDrawdown, 130)
        XCTAssertEqual(r.maxDrawdownPercentOfPeak ?? 0, 1.3, accuracy: 0.0001)
        XCTAssertEqual(r.maxConsecutiveLosses, 2)
        XCTAssertEqual(r.maxConsecutiveWins, 1)
        XCTAssertEqual(r.equityCurve.map { $0.cumulativePnL }, [100, 50, -30, 10])
        XCTAssertEqual(r.dailyPnL.count, 4)
    }

    func testOpenTradesExcludedAndBreakdowns() {
        let open = TradeInput(symbol: "TSLA", assetClass: .usStock, side: .long, fills: [
            fill(.open, "2024-03-05T09:00:00Z", "10", "1"),
        ])
        let trades = [
            trade(pnl: 100, day: 1, setup: "Breakout", tags: ["a", "b"]),
            trade(pnl: -50, day: 2, setup: "Breakout"),
            trade(pnl: 30, day: 3),
            open,
        ]
        let r = PerformanceAnalyzer.analyze(trades, calendar: utc)
        XCTAssertEqual(r.openTrades, 1)
        XCTAssertEqual(r.totalClosedTrades, 3)
        let setups = r.breakdowns[.setup] ?? []
        XCTAssertEqual(setups.first?.key, "Breakout")
        XCTAssertEqual(setups.first?.netPnL, 50)
        XCTAssertTrue(setups.contains { $0.key == "No setup" })
        let tags = r.breakdowns[.tag] ?? []
        XCTAssertEqual(tags.count, 3) // a, b, Untagged
        XCTAssertTrue(tags.contains { $0.key == "Untagged" && $0.trades == 2 })
        let hours = r.breakdowns[.hourOfDay] ?? []
        XCTAssertEqual(hours.first?.key, "09:00")
    }
}
