import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class AlpacaConnectorTests: XCTestCase {
    func testMappingAndPagination() async throws {
        let mock = MockHTTPClient { request in
            let token = queryItems(request)["page_token"]
            return (200, try Fixtures.load(token == nil ? "alpaca_page1.json" : "alpaca_page2.json"))
        }
        let connector = AlpacaConnector(
            credentials: ["keyID": "ID", "secretKey": "SEC", "environment": "paper"],
            session: mock,
            pageSize: 2
        )
        let executions = try await connector.fetchExecutions(since: nil)
        XCTAssertEqual(executions.count, 3)

        XCTAssertEqual(mock.requests.count, 2)
        let first = mock.requests[0]
        XCTAssertEqual(first.url?.host, "paper-api.alpaca.markets")
        XCTAssertEqual(first.url?.path, "/v2/account/activities/FILL")
        XCTAssertEqual(first.value(forHTTPHeaderField: "APCA-API-KEY-ID"), "ID")
        XCTAssertEqual(first.value(forHTTPHeaderField: "APCA-API-SECRET-KEY"), "SEC")
        XCTAssertEqual(queryItems(first)["direction"], "asc")
        XCTAssertEqual(queryItems(first)["page_size"], "2")
        XCTAssertEqual(queryItems(mock.requests[1])["page_token"], "20240102143100000::bbbb-2222")

        let aapl = executions[0]
        XCTAssertEqual(aapl.symbol, "AAPL")
        XCTAssertEqual(aapl.assetClass, .usStock)
        XCTAssertEqual(aapl.side, .buy)
        XCTAssertEqual(aapl.quantity, dec("10"))
        XCTAssertEqual(aapl.price, dec("185.50"))
        XCTAssertEqual(aapl.fee, 0)
        XCTAssertEqual(aapl.orderID, "order-1")
        // 2024-01-02T14:30:15.123Z
        XCTAssertEqual(aapl.date.timeIntervalSince1970, 1_704_205_815.123, accuracy: 0.01)

        let tsla = executions[1]
        XCTAssertEqual(tsla.side, .sell) // sell_short
        // Without fractional seconds.
        XCTAssertEqual(tsla.date.timeIntervalSince1970, 1_704_205_860, accuracy: 0.001)

        let btc = executions[2]
        XCTAssertEqual(btc.symbol, "BTCUSD")
        XCTAssertEqual(btc.assetClass, .cryptoSpot)
        XCTAssertEqual(btc.date.timeIntervalSince1970, 1_704_276_000.5, accuracy: 0.01)
    }

    func testLiveEnvironmentHost() async throws {
        let mock = MockHTTPClient { _ in (200, Data("[]".utf8)) }
        let connector = AlpacaConnector(credentials: ["keyID": "ID", "secretKey": "SEC", "environment": "live"], session: mock)
        let result = try await connector.fetchExecutions(since: Date(timeIntervalSince1970: 1_704_067_200))
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(mock.requests.first?.url?.host, "api.alpaca.markets")
        XCTAssertEqual(queryItems(try XCTUnwrap(mock.requests.first))["after"], "2024-01-01T00:00:00Z")
    }
}
