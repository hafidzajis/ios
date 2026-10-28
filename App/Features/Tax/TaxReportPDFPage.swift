import SwiftUI
import TradeLogCore

/// One A4 page of the tax report PDF. Page 0 also carries the summary.
struct TaxReportPDFPage: View {
    let report: TaxReport
    let rows: [TaxDisposal]
    let pageIndex: Int
    let pageCount: Int

    private func myr(_ v: Decimal) -> String { MoneyFormat.string(v, currencyCode: "MYR") }
    private func date(_ d: Date) -> String { d.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TradeLog Tax Report \(String(report.year))").font(.title2.bold())
                Spacer()
                Text("Page \(pageIndex + 1) of \(pageCount)").font(.caption)
            }
            Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)). All amounts in MYR.")
                .font(.caption).foregroundStyle(.gray)

            if pageIndex == 0 {
                Text("Summary").font(.headline).padding(.top, 4)
                ForEach(report.summary) { s in
                    HStack {
                        Text(s.assetClass.displayName).frame(width: 110, alignment: .leading)
                        Text("\(s.disposals) disp.").frame(width: 60, alignment: .leading)
                        Spacer()
                        Text("Proceeds \(myr(s.proceedsMYR))")
                        Text("Cost \(myr(s.costMYR))")
                        Text("Net \(myr(s.netMYR))").bold()
                    }
                    .font(.caption2)
                }
                HStack {
                    Spacer()
                    Text("Total net: \(myr(report.totalNetMYR))").font(.subheadline.bold())
                }
                if !report.missingRateDays.isEmpty {
                    Text("Warning: \(report.missingRateDays.count) days have no BNM rate.")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            Text("Disposals").font(.headline).padding(.top, 4)
            HStack {
                Text("Symbol").frame(width: 70, alignment: .leading)
                Text("Qty").frame(width: 60, alignment: .trailing)
                Text("Acquired").frame(width: 66, alignment: .leading).padding(.leading, 8)
                Text("Disposed").frame(width: 66, alignment: .leading)
                Spacer()
                Text("Cost").frame(width: 70, alignment: .trailing)
                Text("Proceeds").frame(width: 70, alignment: .trailing)
                Text("Gain").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .bold))
            Divider()
            ForEach(rows) { d in
                HStack {
                    Text(d.symbol).frame(width: 70, alignment: .leading)
                    Text(Fmt.plain(d.quantity)).frame(width: 60, alignment: .trailing)
                    Text(date(d.acquiredDate)).frame(width: 66, alignment: .leading).padding(.leading, 8)
                    Text(date(d.disposedDate)).frame(width: 66, alignment: .leading)
                    Spacer()
                    Text(Fmt.decimal(d.costMYR)).frame(width: 70, alignment: .trailing)
                    Text(Fmt.decimal(d.proceedsMYR)).frame(width: 70, alignment: .trailing)
                    Text(Fmt.decimal(d.gainMYR)).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 8))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(TaxDisclaimer.text).font(.system(size: 7)).foregroundStyle(.gray)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color.white)
    }
}
