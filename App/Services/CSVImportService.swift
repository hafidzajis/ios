import Foundation
import SwiftData
import TradeLogCore
import TradeLogIntegrations

@MainActor
enum CSVImportService {
    static func readText(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    static func headers(in text: String) -> [String] {
        CSVExecutionImporter.headers(in: text)
    }

    static func previewRows(in text: String, limit: Int = 6) -> [[String]] {
        Array(CSVParser.parse(text).prefix(limit))
    }

    static func guessMapping(headers: [String], defaultAssetClass: AssetClass) -> CSVColumnMapping {
        if let guessed = CSVExecutionImporter.guessMapping(headers: headers, defaultAssetClass: defaultAssetClass) {
            return guessed
        }
        let first = headers.first ?? ""
        return CSVColumnMapping(date: first, symbol: first, side: first, quantity: first, price: first, defaultAssetClass: defaultAssetClass)
    }

    static func importCSV(text: String, mapping: CSVColumnMapping, account: Account?, context: ModelContext) throws -> ImportResult {
        let executions = try CSVExecutionImporter.parse(text, mapping: mapping, source: "csv")
        return try ImportMerger.merge(executions: executions, account: account, context: context)
    }
}
