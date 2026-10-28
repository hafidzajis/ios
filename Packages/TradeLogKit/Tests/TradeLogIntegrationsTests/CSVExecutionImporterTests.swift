import Foundation
import XCTest
import TradeLogCore
import TradeLogIntegrations

final class CSVExecutionImporterTests: XCTestCase {
    private let sample = """
    Name,Symbol,Side,Status,Filled Qty,Avg Price,Placed Time,Filled Time,Commission
    Apple Inc,AAPL,Buy,Filled,10,$185.50,01/02/2024 09:29:00 EST,01/02/2024 09:30:15 EST,$0.00
    Tesla Inc,TSLA,Sell,Filled,5,"$1,250.75",01/03/2024 10:14:00 EST,01/03/2024 10:15:00 EST,0.99
    Nvidia,NVDA,,Filled,-3,500.00,01/04/2024 10:59:00 EST,01/04/2024 11:00:00 EST,0
    Bad Row,XXXX,Buy,Filled,abc,10,x,not a date,0
    """

    func testHeadersAndGuessedMapping() throws {
        let headers = CSVExecutionImporter.headers(in: sample)
        XCTAssertEqual(headers.first, "Name")
        XCTAssertEqual(headers.count, 9)
        let mapping = try XCTUnwrap(CSVExecutionImporter.guessMapping(headers: headers, defaultAssetClass: .usStock))
        XCTAssertEqual(mapping.date, "Filled Time")
        XCTAssertEqual(mapping.symbol, "Symbol")
        XCTAssertEqual(mapping.side, "Side")
        XCTAssertEqual(mapping.quantity, "Filled Qty")
        XCTAssertEqual(mapping.price, "Avg Price")
        XCTAssertEqual(mapping.fee, "Commission")
        XCTAssertEqual(mapping.defaultAssetClass, .usStock)
    }

    func testGuessMappingFailsWithoutRequiredColumns() {
        XCTAssertNil(CSVExecutionImporter.guessMapping(headers: ["Foo", "Bar"], defaultAssetClass: .usStock))
    }

    func testParseWebullStyleSample() throws {
        let headers = CSVExecutionImporter.headers(in: sample)
        let mapping = try XCTUnwrap(CSVExecutionImporter.guessMapping(headers: headers, defaultAssetClass: .usStock))
        let executions = try CSVExecutionImporter.parse(sample, mapping: mapping, source: "csv-webull")
        XCTAssertEqual(executions.count, 3) // bad row skipped

        let aapl = executions[0]
        XCTAssertEqual(aapl.source, "csv-webull")
        XCTAssertEqual(aapl.symbol, "AAPL")
        XCTAssertEqual(aapl.side, .buy)
        XCTAssertEqual(aapl.quantity, dec("10"))
        XCTAssertEqual(aapl.price, dec("185.50"))
        XCTAssertEqual(aapl.fee, 0)
        XCTAssertEqual(aapl.assetClass, .usStock)
        // 01/02/2024 09:30:15 EST = 14:30:15Z
        XCTAssertEqual(aapl.date.timeIntervalSince1970, 1_704_205_815, accuracy: 0.001)

        let tsla = executions[1]
        XCTAssertEqual(tsla.side, .sell)
        XCTAssertEqual(tsla.price, dec("1250.75"))
        XCTAssertEqual(tsla.fee, dec("0.99"))

        let nvda = executions[2]
        XCTAssertEqual(nvda.side, .sell) // inferred from the negative quantity
        XCTAssertEqual(nvda.quantity, dec("3"))

        // Hash ids are stable and unique.
        XCTAssertEqual(Set(executions.map { $0.externalID }).count, 3)
        let again = try CSVExecutionImporter.parse(sample, mapping: mapping, source: "csv-webull")
        XCTAssertEqual(executions.map { $0.externalID }, again.map { $0.externalID })
    }

    func testISODatesIdColumnAndDuplicateIDs() throws {
        let csv = "date,symbol,side,quantity,price,fee,trade id\n" +
            "2024-01-02T14:30:00Z,BTC/USDT,BUY,0.5,42000,1.5,A1\n" +
            "2024-01-02T14:31:00Z,BTC/USDT,sold,0.5,42100,1.5,A1\n"
        let mapping = CSVColumnMapping(
            date: "date", symbol: "symbol", side: "side", quantity: "quantity", price: "price",
            fee: "fee", externalID: "trade id", defaultAssetClass: .cryptoSpot
        )
        let executions = try CSVExecutionImporter.parse(csv, mapping: mapping, source: "csv")
        XCTAssertEqual(executions.count, 2)
        XCTAssertEqual(executions[0].symbol, "BTCUSDT")
        XCTAssertEqual(executions[0].externalID, "A1")
        XCTAssertEqual(executions[1].externalID, "A1#2")
        XCTAssertEqual(executions[1].side, .sell)
        XCTAssertEqual(executions[0].date.timeIntervalSince1970, 1_704_205_800, accuracy: 0.001)
    }

    func testCustomDateFormatAndTimeZone() throws {
        let csv = "when,sym,dir,qty,px\n05/01/2024 15:00,AAPL,B,1,100\n"
        let mapping = CSVColumnMapping(
            date: "when", symbol: "sym", side: "dir", quantity: "qty", price: "px",
            dateFormat: "dd/MM/yyyy HH:mm", timeZoneID: "Asia/Kuala_Lumpur", defaultAssetClass: .usStock
        )
        let executions = try CSVExecutionImporter.parse(csv, mapping: mapping, source: "csv")
        // 5 Jan 2024 15:00 MYT = 07:00Z
        XCTAssertEqual(executions.first?.date.timeIntervalSince1970 ?? 0, 1_704_438_000, accuracy: 0.001)
    }

    func testThrowsWhenNothingParsed() {
        let csv = "date,symbol,side,quantity,price\nnot-a-date,AAPL,buy,1,1\n"
        let mapping = CSVColumnMapping(date: "date", symbol: "symbol", side: "side", quantity: "quantity", price: "price", defaultAssetClass: .usStock)
        XCTAssertThrowsError(try CSVExecutionImporter.parse(csv, mapping: mapping, source: "csv"))
    }

    func testMissingMappedColumnThrows() {
        let csv = "date,symbol\n2024-01-02,AAPL\n"
        let mapping = CSVColumnMapping(date: "date", symbol: "symbol", side: "side", quantity: "quantity", price: "price", defaultAssetClass: .usStock)
        XCTAssertThrowsError(try CSVExecutionImporter.parse(csv, mapping: mapping, source: "csv"))
    }
}
