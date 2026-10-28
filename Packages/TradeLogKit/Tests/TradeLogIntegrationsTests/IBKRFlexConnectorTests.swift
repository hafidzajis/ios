import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class IBKRFlexConnectorTests: XCTestCase {
    private let sendPath = "/AccountManagement/FlexWebService/SendRequest"
    private let getPath = "/AccountManagement/FlexWebService/GetStatement"

    func testParsesStatementXML() throws {
        let data = try Fixtures.load("ibkr_statement.xml")
        let executions = try IBKRFlexConnector.executions(fromStatementXML: data, since: nil)
        // OPT row skipped.
        XCTAssertEqual(executions.count, 3)

        let buy = executions[0]
        XCTAssertEqual(buy.externalID, "1001")
        XCTAssertEqual(buy.orderID, "9001")
        XCTAssertEqual(buy.symbol, "AAPL")
        XCTAssertEqual(buy.assetClass, .usStock)
        XCTAssertEqual(buy.side, .buy)
        XCTAssertEqual(buy.quantity, dec("10"))
        XCTAssertEqual(buy.price, dec("185.50"))
        XCTAssertEqual(buy.fee, dec("1.00"))
        XCTAssertEqual(buy.feeCurrency, "USD")
        // 2024-01-02 09:30:15 America/New_York (EST, UTC-5) = 14:30:15Z
        XCTAssertEqual(buy.date.timeIntervalSince1970, 1_704_205_815, accuracy: 0.001)

        let sell = executions[1]
        XCTAssertEqual(sell.side, .sell)
        XCTAssertEqual(sell.quantity, dec("10")) // magnitude of -10
        XCTAssertEqual(sell.fee, dec("1.05"))

        let crypto = executions[2]
        XCTAssertEqual(crypto.assetClass, .cryptoSpot)
        XCTAssertEqual(crypto.symbol, "BTCUSD")
        XCTAssertEqual(crypto.quantity, dec("0.01"))
        // tradeDate + tradeTime fallback: 2024-01-04 12:00:00 EST = 17:00Z
        XCTAssertEqual(crypto.date.timeIntervalSince1970, 1_704_387_600, accuracy: 0.001)
    }

    func testSinceFilter() throws {
        let data = try Fixtures.load("ibkr_statement.xml")
        let since = Date(timeIntervalSince1970: 1_704_250_000) // after the first buy, before the sell
        let executions = try IBKRFlexConnector.executions(fromStatementXML: data, since: since)
        XCTAssertEqual(executions.map { $0.externalID }, ["1002", "1004"])
    }

    func testTwoStepFlowWithRetryOn1019() async throws {
        let counter = CallCounter()
        let sendPath = self.sendPath
        let getPath = self.getPath
        let mock = MockHTTPClient { request in
            let path = request.url?.path ?? ""
            if path == sendPath { return (200, try Fixtures.load("ibkr_send.xml")) }
            if path == getPath {
                return (200, try Fixtures.load(counter.next() == 1 ? "ibkr_generating.xml" : "ibkr_statement.xml"))
            }
            return (404, Data())
        }
        let connector = IBKRFlexConnector(
            credentials: ["token": "TOK", "queryID": "777"],
            session: mock,
            maxRetries: 5,
            retryDelaySeconds: 0
        )
        let executions = try await connector.fetchExecutions(since: nil)
        XCTAssertEqual(executions.count, 3)
        XCTAssertEqual(mock.requests.count, 3) // send + generating + statement
        let step1 = queryItems(mock.requests[0])
        XCTAssertEqual(step1["t"], "TOK")
        XCTAssertEqual(step1["q"], "777")
        XCTAssertEqual(step1["v"], "3")
        let step2 = queryItems(mock.requests[1])
        XCTAssertEqual(step2["q"], "1234567890")
        XCTAssertEqual(step2["t"], "TOK")
        XCTAssertEqual(mock.requests[1].url?.host, "gdcdyn.interactivebrokers.com")
    }

    func testGivesUpAfterMaxRetries() async {
        let sendPath = self.sendPath
        let mock = MockHTTPClient { request in
            if request.url?.path == sendPath { return (200, try Fixtures.load("ibkr_send.xml")) }
            return (200, try Fixtures.load("ibkr_generating.xml"))
        }
        let connector = IBKRFlexConnector(
            credentials: ["token": "TOK", "queryID": "777"], session: mock, maxRetries: 2, retryDelaySeconds: 0
        )
        do {
            _ = try await connector.fetchExecutions(since: nil)
            XCTFail("expected error")
        } catch let error as IntegrationError {
            guard case .http(let status, _) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(status, 1019)
        } catch {
            XCTFail("wrong error \(error)")
        }
        XCTAssertEqual(mock.requests.count, 4) // send + 3 statement attempts
    }
}
