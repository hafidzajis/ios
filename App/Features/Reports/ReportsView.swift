import SwiftUI
import SwiftData
import Charts
import TradeLogCore

struct ReportsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]

    @State private var dimension: BreakdownDimension = .setup
    @State private var range: DateRange = .all

    private var filtered: [Trade] { TradeFilter(range: range).apply(trades) }

    var body: some View {
        let list = filtered
        let report = PerformanceAnalyzer.analyze(list.snapshots)
        let rows = (report.breakdowns[dimension] ?? []).sorted { $0.netPnL > $1.netPnL }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    if sizeClass == .compact {
                        Picker("Breakdown", selection: $dimension) {
                            ForEach(BreakdownDimension.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("Breakdown", selection: $dimension) {
                            ForEach(BreakdownDimension.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if rows.isEmpty {
                    EmptyStateView(title: "No data", systemImage: "chart.bar.xaxis",
                                   message: "Close some trades to see breakdowns by \(dimension.title.lowercased()).")
                        .frame(minHeight: 240)
                } else {
                    barChart(rows)
                    table(rows)
                }
                histogram(list)
            }
            .padding(16)
        }
        .navigationTitle("Reports")
    }

    private func barChart(_ rows: [BreakdownRow]) -> some View {
        card("Net P&L by \(dimension.title.lowercased())") {
            Chart(rows) { row in
                BarMark(x: .value(dimension.title, row.key), y: .value("Net P&L", settings.convert(row.netPnL).doubleValue))
                    .foregroundStyle(row.netPnL >= 0 ? Color.green : Color.red)
            }
            .frame(height: 220)
        }
    }

    private func table(_ rows: [BreakdownRow]) -> some View {
        card("Details") {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(dimension.title).gridColumnAlignment(.leading)
                    Text("Trades"); Text("Win %"); Text("Net"); Text("Avg R")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.key).gridColumnAlignment(.leading).lineLimit(1)
                        Text("\(row.trades)")
                        Text(Fmt.percent(row.winRate, digits: 0))
                        PnLText(value: row.netPnL)
                        Text(Fmt.r(row.averageR))
                    }
                    .font(.footnote.monospacedDigit())
                }
            }
        }
    }

    private struct RBucket: Identifiable {
        let value: Double
        let count: Int
        var id: Double { value }
        var label: String { value.formatted(.number.precision(.fractionLength(1))) + "R" }
    }

    /// Distribution of realized R multiples, bucketed to 0.5R and clamped to [-3, 5].
    private func histogram(_ list: [Trade]) -> some View {
        var counts: [Double: Int] = [:]
        for t in list {
            guard let r = t.cachedRMultiple?.doubleValue else { continue }
            let bucket = (min(max(r, -3), 5) * 2).rounded(.down) / 2
            counts[bucket, default: 0] += 1
        }
        let buckets = counts.keys.sorted().map { RBucket(value: $0, count: counts[$0] ?? 0) }
        return card("R-multiple distribution") {
            if buckets.isEmpty {
                Text("Set a stop loss on your trades to get R multiples.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(buckets) { b in
                    BarMark(x: .value("R", b.label), y: .value("Trades", b.count))
                        .foregroundStyle(b.value >= 0 ? Color.green : Color.red)
                }
                .frame(height: 180)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
