import XCTest
@testable import TradeLogCore

final class TaxReportTests: XCTestCase {
    private let rates = FXRateTable(rates: [
        "2024-03-01": d("4.0"),
        "2024-03-10": d("4.5"),
        "2024-03-20": d("4.2"),
    ])

    private func spotTrade(_ fills: [FillInput], symbol: String = "AAPL") -> TradeInput {
        return TradeInput(symbol: symbol, assetClass: .usStock, side: .long, fills: fills)
    }

    func testDayKeyAndRateLookup() {
        XCTAssertEqual(FXRateTable.dayKey(for: date("2024-03-01T20:00:00Z")), "2024-03-02") // KL is UTC+8
        XCTAssertEqual(rates.rate(on: date("2024-03-01T04:00:00Z")), d("4.0"))
        XCTAssertEqual(rates.rate(on: date("2024-03-13T04:00:00Z")), d("4.5")) // 3 days earlier
        XCTAssertNil(rates.rate(on: date("2024-03-30T04:00:00Z")))
    }

    func testFifoSpansTwoLots() {
        let trade = spotTrade([
            fill(.open, "2024-03-01T04:00:00Z", "100", "10"),
            fill(.open, "2024-03-10T04:00:00Z", "110", "10"),
            fill(.close, "2024-03-20T04:00:00Z", "120", "15"),
        ])
        let report = TaxReportBuilder.build(trades: [trade], year: 2024, rates: rates)
        XCTAssertEqual(report.disposals.count, 2)
        let first = report.disposals[0]
        XCTAssertEqual(first.quantity, 10)
        XCTAssertEqual(first.costMYR, 4000)
        XCTAssertEqual(first.proceedsMYR, 5040)
        XCTAssertEqual(first.gainMYR, 1040)
        let second = report.disposals[1]
        XCTAssertEqual(second.quantity, 5)
        XCTAssertEqual(second.costMYR, 2475)
        XCTAssertEqual(second.proceedsMYR, 2520)
        XCTAssertEqual(second.gainMYR, 45)
        XCTAssertEqual(report.totalNetMYR, 1085)
        XCTAssertEqual(report.summary.count, 1)
        XCTAssertEqual(report.summary[0].gainsMYR, 1085)
        XCTAssertEqual(report.openLotsAtYearEnd.count, 1)
        XCTAssertEqual(report.openLotsAtYearEnd[0].quantity, 5)
        XCTAssertTrue(report.missingRateDays.isEmpty)
    }

    func testPoolsAcrossTrades() {
        let t1 = spotTrade([fill(.open, "2024-03-01T04:00:00Z", "100", "10")])
        let t2 = spotTrade([
            fill(.open, "2024-03-10T04:00:00Z", "110", "10"),
            fill(.close, "2024-03-20T04:00:00Z", "120", "10", fee: "2"),
        ])
        let report = TaxReportBuilder.build(trades: [t1, t2], year: 2024, rates: rates)
        XCTAssertEqual(report.disposals.count, 1)
        XCTAssertEqual(report.disposals[0].costUSD, 1000) // FIFO takes the first lot (from the other trade)
        XCTAssertEqual(report.disposals[0].feesUSD, 2)
        XCTAssertEqual(report.disposals[0].feesMYR, d("8.4"))
    }

    func testYearFilter() {
        let trade = spotTrade([
            fill(.open, "2023-03-01T04:00:00Z", "100", "10"),
            fill(.close, "2023-03-20T04:00:00Z", "120", "5"),
            fill(.close, "2024-03-20T04:00:00Z", "130", "5"),
        ])
        let r2023 = TaxReportBuilder.build(trades: [trade], year: 2023, rates: FXRateTable(rates: [
            "2023-03-01": 4, "2023-03-20": 4,
        ]))
        XCTAssertEqual(r2023.disposals.count, 1)
        XCTAssertEqual(r2023.disposals[0].quantity, 5)
        let tableFor2024 = FXRateTable(rates: ["2023-03-01": 4, "2024-03-20": d("4.2")])
        let r2024 = TaxReportBuilder.build(trades: [trade], year: 2024, rates: tableFor2024)
        XCTAssertEqual(r2024.disposals.count, 1)
        XCTAssertEqual(r2024.disposals[0].proceedsUSD, 650)
        XCTAssertEqual(r2024.disposals[0].costUSD, 500)
        XCTAssertTrue(r2024.openLotsAtYearEnd.isEmpty)
    }

    func testMissingRate() {
        let trade = spotTrade([
            fill(.open, "2024-06-01T04:00:00Z", "100", "1"),
            fill(.close, "2024-06-20T04:00:00Z", "120", "1"),
        ])
        let report = TaxReportBuilder.build(trades: [trade], year: 2024, rates: rates)
        XCTAssertEqual(report.disposals.count, 1)
        XCTAssertEqual(report.disposals[0].gainMYR, 0)
        XCTAssertEqual(report.missingRateDays, ["2024-06-01", "2024-06-20"])
        let required = TaxReportBuilder.requiredRateDays(trades: [trade], year: 2024)
        XCTAssertEqual(required, ["2024-06-01", "2024-06-20"])
    }

    func testShortThenCover() {
        let trade = TradeInput(symbol: "TSLA", assetClass: .usStock, side: .short, fills: [
            fill(.open, "2024-03-01T04:00:00Z", "100", "10"),
            fill(.close, "2024-03-20T04:00:00Z", "90", "10"),
        ])
        let report = TaxReportBuilder.build(trades: [trade], year: 2024, rates: rates)
        XCTAssertEqual(report.disposals.count, 1)
        let disposal = report.disposals[0]
        XCTAssertEqual(disposal.side, .short)
        XCTAssertEqual(disposal.proceedsMYR, 4000) // 1000 * 4.0 (sale)
        XCTAssertEqual(disposal.costMYR, 3780) // 900 * 4.2 (cover)
        XCTAssertEqual(disposal.gainMYR, 220)
    }

    func testPerp() {
        let trade = TradeInput(symbol: "BTCUSDT", assetClass: .cryptoPerp, side: .long, leverage: 5, fills: [
            fill(.open, "2024-03-01T04:00:00Z", "100", "10"),
            fill(.close, "2024-03-20T04:00:00Z", "110", "10", fee: "5"),
        ], fundingFees: 5)
        let report = TaxReportBuilder.build(trades: [trade], year: 2024, rates: rates)
        XCTAssertEqual(report.disposals.count, 1)
        let disposal = report.disposals[0]
        XCTAssertEqual(disposal.method, .derivativePnL)
        XCTAssertEqual(disposal.costUSD, 1000)
        XCTAssertEqual(disposal.proceedsUSD, 1100)
        XCTAssertEqual(disposal.feesUSD, 10)
        XCTAssertEqual(disposal.gainMYR, (1100 - 1000 - 10) * d("4.2"))
        XCTAssertEqual(report.summary.first?.assetClass, .cryptoPerp)
    }

    func testCSV() {
        let trade = spotTrade([
            fill(.open, "2024-03-01T04:00:00Z", "100", "1"),
            fill(.close, "2024-03-20T04:00:00Z", "120", "1"),
        ])
        let report = TaxReportBuilder.build(trades: [trade], year: 2024, rates: rates)
        let rows = CSVParser.parse(report.csv())
        XCTAssertEqual(rows[0][0], "Year")
        XCTAssertEqual(rows[1][1], "AAPL")
        XCTAssertTrue(rows.contains { $0.first == "TOTAL" })
    }
}
