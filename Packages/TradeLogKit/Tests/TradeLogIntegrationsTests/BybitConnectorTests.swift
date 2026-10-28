import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class BybitConnectorTests: XCTestCase {
    private func makeMock() -> MockHTTPClient {
        MockHTTPClient { request in
            let category = queryItems(request)["category"]
            return (200, try Fixtures.load(category == "linear" ? "bybit_linear.json" : "bybit_spot.json"))
        }
    }

    func testMappingSpotAndLinear() async throws {
        let mock = makeMock()
        let connector = BybitConnector(credentials: ["apiKey": "KEY", "apiSecret": "SECRET"], session: mock)
        let executions = try await connector.fetchExecutions(since: nil)
        // Spot trade + linear trade; the linear "Funding" row is skipped.
        XCTAssertEqual(executions.count, 2)

        let spot = try XCTUnwrap(executions.first { $0.assetClass == .cryptoSpot })
        XCTAssertEqual(spot.externalID, "2100000000000000001")
        XCTAssertEqual(spot.symbol, "ETHUSDT")
        XCTAssertEqual(spot.side, .buy)
        XCTAssertEqual(spot.quantity, dec("0.1"))
        XCTAssertEqual(spot.price, dec("2300.5"))
        XCTAssertEqual(spot.fee, dec("0.0001"))
        XCTAssertEqual(spot.feeCurrency, "ETH")
        XCTAssertEqual(spot.orderID, "1400000000000000001")

        let perp = try XCTUnwrap(executions.first { $0.assetClass == .cryptoPerp })
        XCTAssertEqual(perp.side, .sell)
        XCTAssertEqual(perp.feeCurrency, "USDT")
        XCTAssertEqual(perp.fee, dec("2.31"))
        XCTAssertEqual(perp.date.timeIntervalSince1970, 1_704_153_600, accuracy: 0.001)
    }

    func testHeadersAndSignature() async throws {
        let mock = makeMock()
        let connector = BybitConnector(credentials: ["apiKey": "KEY", "apiSecret": "SECRET"], session: mock)
        _ = try await connector.fetchExecutions(since: nil)
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-BAPI-API-KEY"), "KEY")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-BAPI-RECV-WINDOW"), "5000")
        let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-BAPI-TIMESTAMP"))
        let query = try XCTUnwrap(request.url?.query)
        let expected = HMACSigner.sha256Hex(message: timestamp + "KEY" + "5000" + query, secret: "SECRET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-BAPI-SIGN"), expected)
    }

    func testRetCodeErrorBecomesHTTPError() async {
        let mock = MockHTTPClient { _ in
            (200, Data("{\"retCode\":10003,\"retMsg\":\"API key is invalid.\",\"result\":{}}".utf8))
        }
        let connector = BybitConnector(credentials: ["apiKey": "KEY", "apiSecret": "SECRET"], session: mock)
        do {
            _ = try await connector.fetchExecutions(since: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? IntegrationError, IntegrationError.http(status: 10003, body: "API key is invalid."))
        }
    }

    func testSinceIsChunkedInSevenDayWindows() async throws {
        let mock = makeMock()
        let connector = BybitConnector(credentials: ["apiKey": "KEY", "apiSecret": "SECRET"], session: mock)
        let since = Date().addingTimeInterval(-15 * 86400)
        _ = try await connector.fetchExecutions(since: since)
        // 15 days -> 3 windows per category, 2 categories.
        XCTAssertEqual(mock.requests.count, 6)
        for request in mock.requests {
            let items = queryItems(request)
            let start = try XCTUnwrap(Double(items["startTime"] ?? ""))
            let end = try XCTUnwrap(Double(items["endTime"] ?? ""))
            XCTAssertLessThanOrEqual(end - start, 7 * 86400 * 1000)
        }
    }
}
