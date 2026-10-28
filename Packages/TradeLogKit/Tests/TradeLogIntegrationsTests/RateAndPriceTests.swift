import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class BNMRateProviderTests: XCTestCase {
    private func kualaLumpurNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testDayKeyUsesKualaLumpur() {
        // 2024-01-05T17:00:00Z is already 2024-01-06 01:00 in Kuala Lumpur.
        let date = Date(timeIntervalSince1970: 1_704_474_000)
        XCTAssertEqual(BNMRateProvider.dayKey(for: date), "2024-01-06")
    }

    func testParsesDayRate() async throws {
        let mock = MockHTTPClient(routes: ["/public/exchange-rate/USD/date/2024-01-05": "bnm_usd.json"])
        let provider = BNMRateProvider(http: mock)
        let rate = try await provider.usdToMYR(on: kualaLumpurNoon(2024, 1, 5))
        XCTAssertEqual(rate, dec("4.683"))
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.BNM.API.v1+json")
        XCTAssertEqual(queryItems(request)["session"], "1700")
        XCTAssertEqual(queryItems(request)["quote"], "rm")

        // Cached: no further request.
        _ = try await provider.usdToMYR(on: kualaLumpurNoon(2024, 1, 5))
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testWeekendWalksBackToFriday() async throws {
        let mock = MockHTTPClient(routes: ["/public/exchange-rate/USD/date/2024-01-05": "bnm_usd.json"])
        let provider = BNMRateProvider(http: mock)
        // Sunday 2024-01-07 -> 404, Saturday -> 404, Friday -> 200.
        let rate = try await provider.usdToMYR(on: kualaLumpurNoon(2024, 1, 7))
        XCTAssertEqual(rate, dec("4.683"))
        XCTAssertEqual(mock.requests.count, 3)
    }

    func testThrowsWhenNoRateWithinSevenDays() async {
        let mock = MockHTTPClient(routes: [:]) // everything 404
        let provider = BNMRateProvider(http: mock)
        do {
            _ = try await provider.usdToMYR(on: kualaLumpurNoon(2024, 1, 7))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(mock.requests.count, 8) // day itself + 7 days back
        }
    }

    func testBatchRatesUseMonthEndpoint() async {
        let mock = MockHTTPClient(routes: ["/public/exchange-rate/USD/year/2024/month/1": "bnm_month.json"])
        let provider = BNMRateProvider(http: mock)
        let rates = await provider.rates(for: ["2024-01-03", "2024-01-05", "2024-01-06"])
        XCTAssertEqual(rates["2024-01-03"], dec("4.615"))
        XCTAssertEqual(rates["2024-01-05"], dec("4.683"))
        XCTAssertEqual(rates["2024-01-06"], dec("4.683")) // Saturday -> Friday
        XCTAssertEqual(mock.requests.count, 1)
    }

    func testBatchSkipsFailures() async {
        let mock = MockHTTPClient { _ in (500, Data("boom".utf8)) }
        let provider = BNMRateProvider(http: mock)
        let rates = await provider.rates(for: ["2024-01-03"])
        XCTAssertTrue(rates.isEmpty)
    }
}

final class PriceProviderTests: XCTestCase {
    func testCoinGeckoSymbolMapping() {
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "BTCUSDT"), "bitcoin")
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "BTC"), "bitcoin")
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "btc-usd"), "bitcoin")
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "ETH/USD"), "ethereum")
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "SOLUSDT"), "solana")
        XCTAssertEqual(CoinGeckoPriceProvider.coinID(for: "USDT"), "tether")
        XCTAssertNil(CoinGeckoPriceProvider.coinID(for: "NOTACOINUSDT"))
    }

    func testCoinGeckoQuotesKeyedByInputSymbol() async throws {
        let mock = MockHTTPClient(routes: ["/api/v3/simple/price": "coingecko_simple.json"])
        let provider = CoinGeckoPriceProvider(http: mock)
        let quotes = try await provider.quotes(for: ["BTCUSDT", "ETH", "FOO"], assetClass: .cryptoSpot)
        XCTAssertEqual(Set(quotes.keys), ["BTCUSDT", "ETH"])
        XCTAssertEqual(quotes["BTCUSDT"]?.price, dec("67000.5"))
        XCTAssertEqual(quotes["ETH"]?.price, dec("3500.25"))
        let ids = queryItems(try XCTUnwrap(mock.requests.first))["ids"]
        XCTAssertEqual(ids, "bitcoin,ethereum")
    }

    func testBinancePublicSymbolNormalisation() {
        XCTAssertEqual(BinancePublicPriceProvider.binanceSymbol(for: "BTC"), "BTCUSDT")
        XCTAssertEqual(BinancePublicPriceProvider.binanceSymbol(for: "BTC-USD"), "BTCUSDT")
        XCTAssertEqual(BinancePublicPriceProvider.binanceSymbol(for: "ethusdt"), "ETHUSDT")
    }

    func testBinancePublicQuotes() async throws {
        let mock = MockHTTPClient { _ in
            (200, Data("[{\"symbol\":\"BTCUSDT\",\"price\":\"67000.10\"},{\"symbol\":\"ETHUSDT\",\"price\":\"3500.00\"}]".utf8))
        }
        let provider = BinancePublicPriceProvider(http: mock)
        let quotes = try await provider.quotes(for: ["BTC", "ETHUSDT"], assetClass: .cryptoSpot)
        XCTAssertEqual(quotes["BTC"]?.price, dec("67000.10"))
        XCTAssertEqual(quotes["ETHUSDT"]?.price, dec("3500.00"))
        let symbols = queryItems(try XCTUnwrap(mock.requests.first))["symbols"]
        XCTAssertEqual(symbols, "[\"BTCUSDT\",\"ETHUSDT\"]")
    }

    func testFinnhubSkipsZeroPrice() async throws {
        let mock = MockHTTPClient { request in
            let symbol = queryItems(request)["symbol"]
            let body = symbol == "AAPL" ? "{\"c\":190.25,\"t\":1704067200}" : "{\"c\":0,\"t\":0}"
            return (200, Data(body.utf8))
        }
        let provider = FinnhubPriceProvider(apiKey: "K", http: mock)
        let quotes = try await provider.quotes(for: ["AAPL", "ZZZZ"], assetClass: .usStock)
        XCTAssertEqual(Set(quotes.keys), ["AAPL"])
        XCTAssertEqual(quotes["AAPL"]?.price, dec("190.25"))
    }

    func testCompositeFallsBackToCoinGecko() async throws {
        let mock = MockHTTPClient { request in
            let host = request.url?.host ?? ""
            if host == "api.binance.com" { return (400, Data("{\"code\":-1121}".utf8)) }
            return (200, try Fixtures.load("coingecko_simple.json"))
        }
        let provider = CompositePriceProvider(finnhubAPIKey: nil, http: mock)
        let quotes = try await provider.quotes(for: ["BTCUSDT"], assetClass: .cryptoSpot)
        XCTAssertEqual(quotes["BTCUSDT"]?.price, dec("67000.5"))
        let stocks = try await provider.quotes(for: ["AAPL"], assetClass: .usStock)
        XCTAssertTrue(stocks.isEmpty) // no Finnhub key configured
    }
}
