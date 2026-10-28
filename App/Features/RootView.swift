import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(PurchaseManager.self) private var purchases
    @Environment(PriceService.self) private var prices
    @Environment(BackupService.self) private var backups

    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]

    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactTabs
            } else {
                splitView
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.isLocalOnlyFallback { localOnlyBanner }
        }
        .task {
            SeedData.run(context: context, settings: settings)
            await purchases.start()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await backups.autoBackupIfNeeded(context: context, settings: settings)
            while !Task.isCancelled {
                await prices.refresh(openTrades: trades.filter { $0.isOpen && !$0.isArchived })
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var localOnlyBanner: some View {
        Label("iCloud sync unavailable. Data is stored on this device only.", systemImage: "exclamationmark.icloud")
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.yellow.opacity(0.25))
    }

    // MARK: Regular width: sidebar + detail

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                }
            }
            .navigationTitle("TradeLog")
        } detail: {
            NavigationStack {
                screen(for: selection ?? .dashboard)
            }
            .id(selection)
        }
    }

    // MARK: Compact width: tabs

    private var compactTabs: some View {
        TabView {
            NavigationStack { screen(for: .dashboard) }
                .tabItem { Label("Dashboard", systemImage: SidebarItem.dashboard.systemImage) }
            NavigationStack { screen(for: .trades) }
                .tabItem { Label("Trades", systemImage: SidebarItem.trades.systemImage) }
            NavigationStack { screen(for: .positions) }
                .tabItem { Label("Positions", systemImage: SidebarItem.positions.systemImage) }
            NavigationStack { screen(for: .reports) }
                .tabItem { Label("Reports", systemImage: SidebarItem.reports.systemImage) }
            NavigationStack { moreList }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
    }

    private var moreList: some View {
        List {
            ForEach(SidebarItem.moreSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        NavigationLink(value: item) {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
        .navigationTitle("More")
        .navigationDestination(for: SidebarItem.self) { screen(for: $0) }
    }

    @ViewBuilder
    private func screen(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .trades: TradeListView()
        case .positions: OpenPositionsView()
        case .calendar: CalendarView()
        case .reports: ReportsView()
        case .tax: TaxReportView()
        case .playbooks: PlaybooksView()
        case .tags: TagsView()
        case .accounts: AccountsView()
        case .connections: ConnectionsView()
        case .importCSV: CSVImportView()
        case .backup: BackupView()
        case .settings: SettingsView()
        case .purchase: PurchaseView()
        }
    }
}

extension View {
    /// Registers the trade detail destination for `NavigationLink(value: trade)`.
    func tradeDestinations() -> some View {
        navigationDestination(for: Trade.self) { TradeDetailView(trade: $0) }
    }
}
