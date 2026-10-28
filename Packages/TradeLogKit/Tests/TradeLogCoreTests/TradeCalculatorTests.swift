import XCTest
@testable import TradeLogCore

final class TradeCalculatorTests: XCTestCase {
    func testLongWin() {
        let trade = TradeInput(symbol: "AAPL", assetClass: .usStock, side: .long, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "10"),
            fill(.close, "2024-03-02T14:00:00Z", "110", "10"),
        ])
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.avgEntryPrice, 100)
        XCTAssertEqual(m.avgExitPrice, 110)
        XCTAssertEqual(m.grossRealizedPnL, 100)
        XCTAssertEqual(m.netRealizedPnL, 100)
        XCTAssertEqual(m.outcome, .win)
        XCTAssertEqual(m.remainingQuantity, 0)
        XCTAssertEqual(m.holdingSeconds, 86400)
        XCTAssertEqual(m.closeDate, date("2024-03-02T14:00:00Z"))
    }

    func testShortWin() {
        let trade = TradeInput(symbol: "BTCUSDT", assetClass: .cryptoPerp, side: .short, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "2"),
            fill(.close, "2024-03-01T15:00:00Z", "90", "2", fee: "1"),
        ], fundingFees: d("0.5"))
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.grossRealizedPnL, 20)
        XCTAssertEqual(m.netRealizedPnL, d("18.5"))
        XCTAssertEqual(m.outcome, .win)
    }

    func testLossAndBreakeven() {
        let loss = TradeInput(symbol: "X", assetClass: .usStock, side: .long, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "1"),
            fill(.close, "2024-03-01T15:00:00Z", "90", "1"),
        ])
        XCTAssertEqual(TradeCalculator.metrics(for: loss).outcome, .loss)
        let flat = TradeInput(symbol: "X", assetClass: .usStock, side: .long, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "1"),
            fill(.close, "2024-03-01T15:00:00Z", "100", "1"),
        ])
        XCTAssertEqual(TradeCalculator.metrics(for: flat).outcome, .breakeven)
    }

    func testPartialCloseStaysOpen() {
        let trade = TradeInput(symbol: "AAPL", assetClass: .usStock, side: .long, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "10", fee: "1"),
            fill(.close, "2024-03-02T14:00:00Z", "110", "4", fee: "1"),
        ])
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.remainingQuantity, 6)
        XCTAssertEqual(m.outcome, .open)
        XCTAssertEqual(m.grossRealizedPnL, 40)
        XCTAssertEqual(m.netRealizedPnL, 38)
        XCTAssertNil(m.closeDate)
        XCTAssertNil(m.rMultiple)
        XCTAssertEqual(TradeCalculator.unrealizedPnL(for: trade, metrics: m, currentPrice: 105), 30)
    }

    func testUnrealizedShort() {
        let trade = TradeInput(symbol: "X", assetClass: .usStock, side: .short, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "10"),
        ])
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(TradeCalculator.unrealizedPnL(for: trade, metrics: m, currentPrice: 95), 50)
    }

    func testLeverageMargin() {
        let trade = TradeInput(symbol: "BTCUSDT", assetClass: .cryptoPerp, side: .long, leverage: 10, fills: [
            fill(.open, "2024-03-01T14:00:00Z", "100", "10"),
            fill(.close, "2024-03-01T15:00:00Z", "110", "10"),
        ])
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.positionValue, 1000)
        XCTAssertEqual(m.marginUsed, 100)
        XCTAssertEqual(m.returnOnMargin, 1)
    }

    func testRMultiple() {
        let trade = TradeInput(
            symbol: "AAPL", assetClass: .usStock, side: .long, plannedEntry: 100, stopLoss: 95, takeProfit: 115,
            fills: [
                fill(.open, "2024-03-01T14:00:00Z", "100", "10"),
                fill(.close, "2024-03-02T14:00:00Z", "110", "10", fee: "1"),
            ]
        )
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.plannedRisk, 50)
        XCTAssertEqual(m.plannedRewardRatio, 3)
        XCTAssertEqual(m.netRealizedPnL, 99)
        XCTAssertEqual(m.rMultiple, d("1.98"))
    }

    func testNoFillsIsOpen() {
        let trade = TradeInput(symbol: "X", assetClass: .usStock, side: .long, fills: [])
        let m = TradeCalculator.metrics(for: trade)
        XCTAssertEqual(m.outcome, .open)
        XCTAssertNil(m.avgEntryPrice)
        XCTAssertNil(m.openDate)
    }
}
