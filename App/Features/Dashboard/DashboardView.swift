import SwiftUI
import SwiftData
import Charts
import TradeLogCore

struct DashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var account: Account?
    @State private var range: DateRange = .d30
    @State private var showEditor = false

    private var filtered: [Trade] {
        TradeFilter(account: account, range: range).apply(trades)
    }

    var body: some View {
        let list = filtered
        let report = PerformanceAnalyzer.analyze(list.snapshots)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                if trades.isEmpty {
                    EmptyStateView(title: "No trades yet", systemImage: "chart.line.uptrend.xyaxis",
                                   message: "Add a trade, import a CSV, or connect an exchange to see your stats.")
                        .frame(minHeight: 260)
                } else {
                    kpiGrid(report)
                    equityCard(report)
                    recentCard(list)
                }
            }
            .padding(16)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditor = true } label: { Label("New Trade", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) { TradeEditorView(trade: nil) }
        .tradeDestinations()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if accounts.count > 0 {
                Picker("Account", selection: $account) {
                    Text("All accounts").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            Picker("Range", selection: $range) {
                ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func kpiGrid(_ r: PerformanceReport) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            KPITile(title: "Net P&L", value: settings.signedMoney(r.netPnL),
                    subtitle: "\(r.totalClosedTrades) closed, \(r.openTrades) open", tint: Color.pnl(r.netPnL))
            KPITile(title: "Win rate", value: Fmt.percent(r.winRate), subtitle: "\(r.wins)W / \(r.losses)L / \(r.breakevens)BE")
            KPITile(title: "Profit factor", value: Fmt.number(r.profitFactor))
            KPITile(title: "Expectancy", value: settings.signedMoney(r.expectancy), subtitle: "per trade", tint: Color.pnl(r.expectancy))
            KPITile(title: "Avg R", value: Fmt.r(r.averageR))
            KPITile(title: "Max drawdown", value: settings.money(r.maxDrawdown),
                    subtitle: r.maxDrawdownPercentOfPeak.map { Fmt.percent($0) }, tint: r.maxDrawdown > 0 ? .red : .primary)
        }
    }

    private func equityCard(_ r: PerformanceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equity curve").font(.headline)
            if r.equityCurve.count < 2 {
                Text("Close a few trades to see your equity curve.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(r.equityCurve, id: \.date) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Cumulative P&L", p.cumulativePnL.doubleValue))
                        .foregroundStyle(.blue.opacity(0.15))
                    LineMark(x: .value("Date", p.date), y: .value("Cumulative P&L", p.cumulativePnL.doubleValue))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                }
                .frame(height: 200)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recentCard(_ list: [Trade]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent trades").font(.headline)
            let recent = Array(list.sorted { $0.sortDate > $1.sortDate }.prefix(5))
            if recent.isEmpty {
                Text("No trades in this range.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(recent) { trade in
                NavigationLink(value: trade) {
                    TradeRow(trade: trade)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
