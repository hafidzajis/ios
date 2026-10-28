import SwiftUI
import SwiftData
import TradeLogCore

enum TradeSort: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case bestPnL = "Best P&L"
    case worstPnL = "Worst P&L"
    case symbol = "Symbol"
    var id: String { rawValue }
}

struct TradeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]

    @State private var filter = TradeFilter()
    @State private var sort: TradeSort = .newest
    @State private var showFilters = false
    @State private var showEditor = false
    @State private var showArchived = false

    private var visible: [Trade] {
        var f = filter
        f.includeArchived = showArchived
        let list = f.apply(trades)
        switch sort {
        case .newest: return list.sorted { $0.sortDate > $1.sortDate }
        case .oldest: return list.sorted { $0.sortDate < $1.sortDate }
        case .bestPnL: return list.sorted { $0.cachedNetPnL > $1.cachedNetPnL }
        case .worstPnL: return list.sorted { $0.cachedNetPnL < $1.cachedNetPnL }
        case .symbol: return list.sorted { $0.symbol < $1.symbol }
        }
    }

    var body: some View {
        let list = visible
        List {
            ForEach(list) { trade in
                NavigationLink(value: trade) {
                    TradeRow(trade: trade)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { delete(trade) } label: { Label("Delete", systemImage: "trash") }
                    Button { archive(trade) } label: {
                        Label(trade.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)
                }
            }
        }
        .overlay {
            if trades.isEmpty {
                EmptyStateView(title: "No trades", systemImage: "list.bullet.rectangle",
                               message: "Tap + to log your first trade.")
            } else if list.isEmpty {
                EmptyStateView(title: "No matches", systemImage: "magnifyingglass",
                               message: "Try changing the search or filters.")
            }
        }
        .navigationTitle("Trades")
        .searchable(text: $filter.search, prompt: "Symbol, note, setup or tag")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditor = true } label: { Label("New Trade", systemImage: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showFilters = true } label: {
                    Label("Filters", systemImage: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(TradeSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Show archived", isOn: $showArchived)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showEditor) { TradeEditorView(trade: nil) }
        .sheet(isPresented: $showFilters) { TradeFilterSheet(filter: $filter) }
        .tradeDestinations()
    }

    private func delete(_ trade: Trade) {
        context.delete(trade)
        try? context.save()
    }

    private func archive(_ trade: Trade) {
        trade.isArchived.toggle()
        trade.updatedAt = Date()
        try? context.save()
    }
}

struct TradeFilterSheet: View {
    @Binding var filter: TradeFilter
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Setup.name) private var setups: [Setup]
    @Query(sort: \Tag.name) private var tags: [Tag]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Account", selection: $filter.account) {
                    Text("All").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                }
                Picker("Asset class", selection: $filter.assetClass) {
                    Text("All").tag(AssetClass?.none)
                    ForEach(AssetClass.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Outcome", selection: $filter.outcome) {
                    Text("All").tag(TradeOutcome?.none)
                    ForEach(TradeOutcome.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                Picker("Setup", selection: $filter.setup) {
                    Text("All").tag(Setup?.none)
                    ForEach(setups) { Text($0.name).tag(Optional($0)) }
                }
                Picker("Tag", selection: $filter.tag) {
                    Text("All").tag(Tag?.none)
                    ForEach(tags) { Text($0.name).tag(Optional($0)) }
                }
                Picker("Date range", selection: $filter.range) {
                    ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                }
                Section {
                    Button("Reset filters", role: .destructive) { filter.reset() }
                }
            }
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
