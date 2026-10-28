import XCTest
@testable import TradeLogCore

final class TradeAssemblerTests: XCTestCase {
    private func exec(_ id: String, _ side: ExecutionSide, _ qty: String, _ price: String, _ iso: String,
                      fee: String = "0", feeCurrency: String? = nil, symbol: String = "BTCUSDT") -> ImportedExecution {
        return ImportedExecution(source: "test", externalID: id, symbol: symbol, assetClass: .cryptoSpot, side: side,
                                 quantity: d(qty), price: d(price), fee: d(fee), feeCurrency: feeCurrency, date: date(iso))
    }

    func testPartialFillsOneTrade() {
        let trades = TradeAssembler.assemble([
            exec("1", .buy, "1", "100", "2024-03-01T10:00:00Z"),
            exec("2", .buy, "1", "102", "2024-03-01T10:05:00Z"),
            exec("3", .sell, "1", "110", "2024-03-01T11:00:00Z"),
            exec("4", .sell, "1", "112", "2024-03-01T11:05:00Z"),
        ])
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].side, .long)
        XCTAssertFalse(trades[0].isOpen)
        XCTAssertEqual(trades[0].fills.map { $0.action }, [.open, .open, .close, .close])
        XCTAssertEqual(trades[0].executionIDs.count, 4)
    }

    func testOpenTrade() {
        let trades = TradeAssembler.assemble([
            exec("1", .sell, "2", "100", "2024-03-01T10:00:00Z"),
            exec("2", .buy, "1", "90", "2024-03-01T11:00:00Z"),
        ])
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].side, .short)
        XCTAssertTrue(trades[0].isOpen)
    }

    func testFlipThroughZeroSplitsFee() {
        let trades = TradeAssembler.assemble([
            exec("1", .buy, "1", "100", "2024-03-01T10:00:00Z"),
            exec("2", .sell, "3", "110", "2024-03-01T11:00:00Z", fee: "3", feeCurrency: "USDT"),
            exec("3", .buy, "2", "105", "2024-03-01T12:00:00Z"),
        ])
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(trades[0].side, .long)
        XCTAssertFalse(trades[0].isOpen)
        XCTAssertEqual(trades[0].fills.last?.quantity, 1)
        XCTAssertEqual(trades[0].fills.last?.fee, 1)
        XCTAssertEqual(trades[1].side, .short)
        XCTAssertFalse(trades[1].isOpen)
        XCTAssertEqual(trades[1].fills.first?.action, .open)
        XCTAssertEqual(trades[1].fills.first?.quantity, 2)
        XCTAssertEqual(trades[1].fills.first?.fee, 2)
        XCTAssertEqual(trades[1].fills.last?.action, .close)
    }

    func testDedupeAndForeignFeeCurrency() {
        let a = exec("1", .buy, "1", "100", "2024-03-01T10:00:00Z", fee: "0.001", feeCurrency: "BTC")
        let trades = TradeAssembler.assemble([a, a, exec("2", .sell, "1", "101", "2024-03-01T11:00:00Z", fee: "0.1", feeCurrency: "USDT")])
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].fills.count, 2)
        XCTAssertEqual(trades[0].fills[0].fee, 0)
        XCTAssertEqual(trades[0].fills[1].fee, d("0.1"))
    }

    func testSeparateSymbols() {
        let trades = TradeAssembler.assemble([
            exec("1", .buy, "1", "100", "2024-03-01T10:00:00Z", symbol: "AAA"),
            exec("2", .buy, "1", "100", "2024-03-01T10:01:00Z", symbol: "BBB"),
        ])
        XCTAssertEqual(trades.count, 2)
    }
}
