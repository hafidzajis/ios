import XCTest
import SwiftData
import TradeLogCore
@testable import TradeLog

@MainActor
final class TradeMappingTests: XCTestCase {
    func testModelToTradeInputMappingAndCache() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TradeLogApp.schema, configurations: config)
        let context = ModelContext(container)

        let trade = Trade(symbol: "AAPL", assetClass: .usStock, side: .long)
        context.insert(trade)
        trade.stopLoss = 95
        let open = Fill(action: .open, date: Date(timeIntervalSince1970: 1_700_000_000), price: 100, quantity: 10, fee: 1)
        let close = Fill(action: .close, date: Date(timeIntervalSince1970: 1_700_003_600), price: 110, quantity: 10, fee: 1)
        context.insert(open)
        context.insert(close)
        trade.addFill(open)
        trade.addFill(close)

        let snapshot = trade.snapshot()
        XCTAssertEqual(snapshot.symbol, "AAPL")
        XCTAssertEqual(snapshot.fills.count, 2)
        XCTAssertEqual(snapshot.fills.first?.action, .open)
        XCTAssertEqual(snapshot.stopLoss, 95)

        trade.refreshCache()
        XCTAssertEqual(trade.outcome, .win)
        XCTAssertEqual(trade.cachedNetPnL, 98) // (110 - 100) * 10 - 2 fees
        XCTAssertNotNil(trade.cachedCloseDate)
    }
}
