import SwiftUI
import TradeLogCore

/// Renders SwiftUI pages to a multi-page A4 PDF using ImageRenderer.
@MainActor
enum PDFExporter {
    /// A4 in PostScript points.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let rowsPerPage = 30

    static func render(pages: [AnyView], fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }

    /// Tax report: summary page(s) followed by the disposal table, ~30 rows per page.
    static func taxReport(_ report: TaxReport) throws -> URL {
        let chunks = stride(from: 0, to: max(report.disposals.count, 1), by: rowsPerPage).map { start in
            Array(report.disposals[min(start, report.disposals.count) ..< min(start + rowsPerPage, report.disposals.count)])
        }
        let total = chunks.count
        let pages: [AnyView] = chunks.enumerated().map { index, rows in
            AnyView(
                TaxReportPDFPage(report: report, rows: rows, pageIndex: index, pageCount: total)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .environment(\.colorScheme, .light)
            )
        }
        return try render(pages: pages, fileName: "TradeLog-Tax-\(report.year).pdf")
    }
}
