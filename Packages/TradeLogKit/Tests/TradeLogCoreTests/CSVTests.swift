import XCTest
@testable import TradeLogCore

final class CSVTests: XCTestCase {
    func testRoundTrip() {
        let rows = [
            ["a", "b,c", "d\"e", "line1\nline2"],
            ["", "x", " y ", "\"\""],
        ]
        let text = CSVWriter.write(rows)
        XCTAssertEqual(CSVParser.parse(text), rows)
    }

    func testWriterQuoting() {
        XCTAssertEqual(CSVWriter.write([["a,b", "c"]]), "\"a,b\",c\n")
        XCTAssertEqual(CSVWriter.write([["say \"hi\""]]), "\"say \"\"hi\"\"\"\n")
    }

    func testParseCRLFAndBOMAndNoTrailingNewline() {
        let text = "\u{FEFF}h1,h2\r\n1,\"two, 2\"\r\n3,4"
        XCTAssertEqual(CSVParser.parse(text), [["h1", "h2"], ["1", "two, 2"], ["3", "4"]])
    }

    func testParseTrailingNewlineAndEmptyFields() {
        XCTAssertEqual(CSVParser.parse("a,,c\n"), [["a", "", "c"]])
        XCTAssertEqual(CSVParser.parse(""), [])
    }

    func testQuotedNewlineWithCRLF() {
        XCTAssertEqual(CSVParser.parse("\"a\r\nb\",c\r\n"), [["a\r\nb", "c"]])
    }
}
