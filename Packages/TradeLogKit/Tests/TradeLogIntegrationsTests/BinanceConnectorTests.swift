import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class BinanceConnectorTests: XCTestCase {
    func testDocumentedHMACExample() {
        let secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"
        let query = "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"
        XCTAssertEqual(
            HMACSigner.sha256Hex(message: query, secret: secret),
            "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71"
        )
    }

    func testSpotMappingAndSignedRequest() async throws {
        let mock = MockHTTPClient(routes: ["/api/v3/myTrades": "binance_myTrades.json"])
        let connector = BinanceConnector(
            credentials: ["apiKey": "KEY", "apiSecret": "SECRET", "symbols": "btcusdt", "includeFutures": "false"],
            session: mock
        )
        let executions = try await connector.fetchExecutions(since: nil)
        XCTAssertEqual(executions.count, 2)

        let buy = try XCTUnwrap(executions.first)
        XCTAssertEqual(buy.source, "binance")
        XCTAssertEqual(buy.externalID, "BTCUSDT-28457")
        XCTAssertEqual(buy.orderID, "100234")
        XCTAssertEqual(buy.symbol, "BTCUSDT")
        XCTAssertEqual(buy.assetClass, .cryptoSpot)
        XCTAssertEqual(buy.side, .buy)
        XCTAssertEqual(buy.quantity, dec("0.5"))
        XCTAssertEqual(buy.price, dec("42000.10"))
        XCTAssertEqual(buy.fee, dec("0.0005"))
        XCTAssertEqual(buy.feeCurrency, "BTC")
        XCTAssertEqual(buy.date.timeIntervalSince1970, 1_704_067_200, accuracy: 0.001)

        let sell = executions[1]
        XCTAssertEqual(sell.side, .sell)
        XCTAssertEqual(sell.feeCurrency, "USDT")

        // One request (2 < 1000 rows -> no pagination); check headers and signature.
        XCTAssertEqual(mock.requests.count, 1)
        let request = mock.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MBX-APIKEY"), "KEY")
        let urlString = try XCTUnwrap(request.url?.absoluteString)
        let marker = "&signature="
        let markerRange = try XCTUnwrap(urlString.range(of: marker))
        let signature = String(urlString[markerRange.upperBound...])
        let queryStart = try XCTUnwrap(urlString.firstIndex(of: "?"))
        let signedQuery = String(urlString[urlString.index(after: queryStart)..<markerRange.lowerBound])
        XCTAssertEqual(HMACSigner.sha256Hex(message: signedQuery, secret: "SECRET"), signature)
        let items = queryItems(request)
        XCTAssertEqual(items["symbol"], "BTCUSDT")
        XCTAssertEqual(items["limit"], "1000")
        XCTAssertEqual(items["recvWindow"], "5000")
        XCTAssertNotNil(items["timestamp"])
    }

    func testFuturesMapping() async throws {
        let mock = MockHTTPClient(routes: [
            "/api/v3/myTrades": "binance_myTrades.json",
            "/fapi/v1/userTrades": "binance_userTrades.json",
        ])
        let connector = BinanceConnector(
            credentials: ["apiKey": "KEY", "apiSecret": "SECRET", "symbols": "BTCUSDT", "includeFutures": "true"],
            session: mock
        )
        let executions = try await connector.fetchExecutions(since: nil)
        XCTAssertEqual(executions.count, 3)
        let perp = try XCTUnwrap(executions.first { $0.assetClass == .cryptoPerp })
        XCTAssertEqual(perp.externalID, "F-BTCUSDT-698759")
        XCTAssertEqual(perp.side, .sell)
        XCTAssertEqual(perp.quantity, dec("0.1"))
        XCTAssertEqual(perp.price, dec("42500.5"))
        XCTAssertEqual(perp.fee, dec("1.70002"))
        XCTAssertEqual(perp.reportedRealizedPnL, dec("12.3456"))
    }

    func testMissingSymbolsThrows() async {
        let connector = BinanceConnector(
            credentials: ["apiKey": "KEY", "apiSecret": "SECRET"],
            session: MockHTTPClient(routes: [:])
        )
        do {
            _ = try await connector.fetchExecutions(since: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? IntegrationError, IntegrationError.missingCredential("symbols"))
        }
    }

    func testHTTPErrorIsThrown() async {
        let mock = MockHTTPClient { _ in (401, Data("{\"code\":-2015}".utf8)) }
        let connector = BinanceConnector(
            credentials: ["apiKey": "KEY", "apiSecret": "SECRET", "symbols": "BTCUSDT"],
            session: mock
        )
        do {
            _ = try await connector.fetchExecutions(since: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? IntegrationError, IntegrationError.http(status: 401, body: "{\"code\":-2015}"))
        }
    }

    func testRegistry() {
        XCTAssertEqual(ConnectorRegistry.all.count, 4)
        XCTAssertEqual(ConnectorRegistry.type(for: "binance")?.connectorID, "binance")
        XCTAssertNil(ConnectorRegistry.type(for: "nope"))
    }
}
