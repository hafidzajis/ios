import SwiftUI
import SwiftData
import TradeLogCore

struct OpenPositionsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PriceService.self) private var prices
    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]

    private struct Row: Identifiable {
        let trade: Trade
        let metrics: TradeMetrics
        let price: Decimal?
        var id: PersistentIdentifier { trade.persistentModelID }

        var unrealized: Decimal? {
            price.map { TradeCalculator.unrealizedPnL(for: trade.snapshot(), metrics: metrics, currentPrice: $0) }
        }
        /// Notional value of the remaining position at the current (or entry) price.
        var exposure: Decimal {
            metrics.remainingQuantity * (price ?? metrics.avgEntryPrice ?? 0)
        }
        var margin: Decimal { exposure / max(trade.leverage, 1) }

        func distance(to level: Decimal?) -> Double? {
            guard let level, let price, price > 0 else { return nil }
            return ((level - price) / price).doubleValue
        }
    }

    private var rows: [Row] {
        trades.filter { $0.isOpen && !$0.isArchived }.map { t in
            Row(trade: t, metrics: t.metrics, price: prices.price(for: t))
        }
    }

    var body: some View {
        let list = rows
        List {
            if !list.isEmpty {
                Section {
                    summary(list)
                }
            }
            ForEach(list) { row in
                NavigationLink(value: row.trade) { rowView(row) }
            }
            if let error = prices.lastError {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .overlay {
            if list.isEmpty {
                EmptyStateView(title: "No open positions", systemImage: "scope",
                               message: "Trades with remaining quantity appear here with live prices.")
            }
        }
        .navigationTitle("Open Positions")
        .refreshable { await prices.refresh(openTrades: list.map(\.trade)) }
        .task { await prices.refresh(openTrades: list.map(\.trade)) }
        .tradeDestinations()
    }

    private func summary(_ list: [Row]) -> some View {
        let exposure = list.reduce(Decimal(0)) { $0 + $1.exposure }
        let margin = list.reduce(Decimal(0)) { $0 + $1.margin }
        let unrealized = list.reduce(Decimal(0)) { $0 + ($1.unrealized ?? 0) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            KPITile(title: "Exposure", value: settings.money(exposure))
            KPITile(title: "Margin used", value: settings.money(margin))
            KPITile(title: "Unrealized P&L", value: settings.signedMoney(unrealized), tint: Color.pnl(unrealized))
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.trade.symbol).font(.headline)
                SideBadge(side: row.trade.side)
                if row.trade.leverage > 1 { Text("\(Fmt.plain(row.trade.leverage))x").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let u = row.unrealized { PnLText(value: u).font(.headline) } else { Text("No price").foregroundStyle(.secondary) }
            }
            HStack {
                Text("\(Fmt.plain(row.metrics.remainingQuantity)) @ \(Fmt.plain(row.metrics.avgEntryPrice))")
                Spacer()
                Text("Now \(Fmt.plain(row.price))")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            HStack(spacing: 12) {
                if let d = row.distance(to: row.trade.stopLoss) {
                    Label("SL \(Fmt.percent(d))", systemImage: "arrow.down.to.line").foregroundStyle(.red)
                }
                if let d = row.distance(to: row.trade.takeProfit) {
                    Label("TP \(Fmt.percent(d))", systemImage: "arrow.up.to.line").foregroundStyle(.green)
                }
                Spacer()
                Text("Exposure \(settings.money(row.exposure, fractionDigits: 0))").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
