import SwiftUI
import SwiftData
import TradeLogCore

struct TaxReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(FXRateService.self) private var fx
    @Query(sort: \Trade.createdAt) private var trades: [Trade]
    @Query private var rateRows: [FXRate]

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var showMissing = false
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var exportError: String?

    private var activeTrades: [Trade] { trades.filter { !$0.isArchived } }

    private var years: [Int] {
        let cal = Calendar.current
        var set = Set<Int>()
        for t in activeTrades {
            for f in t.fills ?? [] where f.action == .close { set.insert(cal.component(.year, from: f.date)) }
        }
        set.insert(cal.component(.year, from: Date()))
        return set.sorted(by: >)
    }

    var body: some View {
        let snaps = activeTrades.snapshots
        let required = TaxReportBuilder.requiredRateDays(trades: snaps, year: year)
        let report = TaxReportBuilder.build(trades: snaps, year: year, rates: FXRateService.table(from: rateRows), now: Date())

        List {
            Section {
                Picker("Year of assessment", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                ratesRow(required: required, report: report)
            }
            if !report.missingRateDays.isEmpty {
                Section {
                    Label("\(report.missingRateDays.count) days have no BNM rate, so affected disposals use no conversion until you fetch or enter them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    Button("Enter rates manually") { showMissing = true }
                }
            }
            summarySection(report)
            disposalsSection(report)
            exportSection(report)
            Section { Text(TaxDisclaimer.text).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Tax Report")
        .onChange(of: year) { _, _ in pdfURL = nil; csvURL = nil }
        .sheet(isPresented: $showMissing) {
            MissingRatesSheet(days: report.missingRateDays)
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    // MARK: Sections

    private func ratesRow(required: Set<String>, report: TaxReport) -> some View {
        let have = Set(rateRows.map(\.dayKey))
        let missing = required.subtracting(have)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(required.count - missing.count) of \(required.count) rates cached")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await fx.ensureRates(for: required, context: context) }
                } label: {
                    Label("Fetch BNM rates", systemImage: "arrow.down.circle")
                }
                .disabled(fx.isFetching || missing.isEmpty)
            }
            if fx.isFetching {
                ProgressView(value: fx.progress)
            }
            if let message = fx.lastMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func summarySection(_ report: TaxReport) -> some View {
        Section("Summary (MYR)") {
            if report.summary.isEmpty {
                Text("No disposals in \(String(year)).").foregroundStyle(.secondary)
            }
            ForEach(report.summary) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.assetClass.displayName).font(.headline)
                        Spacer()
                        Text(myr(row.netMYR, signed: true)).foregroundStyle(Color.pnl(row.netMYR)).font(.headline)
                    }
                    Text("\(row.disposals) disposals  |  Proceeds \(myr(row.proceedsMYR))  |  Cost \(myr(row.costMYR))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Gains \(myr(row.gainsMYR))  |  Losses \(myr(row.lossesMYR))  |  Fees \(myr(row.feesMYR))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !report.summary.isEmpty {
                HStack {
                    Text("Total net").font(.headline)
                    Spacer()
                    Text(myr(report.totalNetMYR, signed: true)).foregroundStyle(Color.pnl(report.totalNetMYR)).font(.headline)
                }
            }
            if !report.openLotsAtYearEnd.isEmpty {
                Text("\(report.openLotsAtYearEnd.count) open lots carried past year end.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func disposalsSection(_ report: TaxReport) -> some View {
        Section("Disposals (\(report.disposals.count))") {
            ForEach(report.disposals) { d in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(d.symbol).font(.headline)
                            Text(d.method.title).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.plain(d.quantity))  |  \(d.acquiredDate.formatted(date: .numeric, time: .omitted)) to \(d.disposedDate.formatted(date: .numeric, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(myr(d.gainMYR, signed: true)).foregroundStyle(Color.pnl(d.gainMYR)).monospacedDigit()
                }
            }
        }
    }

    private func exportSection(_ report: TaxReport) -> some View {
        Section("Export") {
            Button {
                do { pdfURL = try PDFExporter.taxReport(report) } catch { exportError = error.localizedDescription }
            } label: { Label("Prepare PDF", systemImage: "doc.richtext") }
            if let pdfURL { ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") } }

            Button {
                do {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("TradeLog-Tax-\(report.year).csv")
                    try report.csv().write(to: url, atomically: true, encoding: .utf8)
                    csvURL = url
                } catch { exportError = error.localizedDescription }
            } label: { Label("Prepare CSV", systemImage: "tablecells") }
            if let csvURL { ShareLink(item: csvURL) { Label("Share CSV", systemImage: "square.and.arrow.up") } }
        }
    }

    private func myr(_ value: Decimal, signed: Bool = false) -> String {
        signed ? MoneyFormat.signed(value, currencyCode: "MYR") : MoneyFormat.string(value, currencyCode: "MYR")
    }
}

struct MissingRatesSheet: View {
    let days: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(FXRateService.self) private var fx
    @State private var values: [String: Decimal] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(days, id: \.self) { day in
                        LabeledContent(day) {
                            DecimalField("MYR per USD", value: Binding(
                                get: { values[day] },
                                set: { values[day] = $0 }
                            ))
                        }
                    }
                } footer: {
                    Text("Enter the BNM USD/MYR middle rate for each day (for example 4.4720).")
                }
            }
            .navigationTitle("Manual Rates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for (day, value) in values {
                            if value > 0 { fx.setManual(dayKey: day, rate: value, context: context) }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
