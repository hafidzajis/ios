import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, trades, positions, calendar
    case reports, tax
    case playbooks, tags, accounts
    case connections, importCSV, backup
    case settings, purchase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .trades: return "Trades"
        case .positions: return "Open Positions"
        case .calendar: return "Calendar"
        case .reports: return "Reports"
        case .tax: return "Tax Report"
        case .playbooks: return "Playbooks"
        case .tags: return "Tags"
        case .accounts: return "Accounts"
        case .connections: return "Connections"
        case .importCSV: return "Import CSV"
        case .backup: return "Backup & Sync"
        case .settings: return "Settings"
        case .purchase: return "Unlock TradeLog"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .trades: return "list.bullet.rectangle"
        case .positions: return "scope"
        case .calendar: return "calendar"
        case .reports: return "chart.bar.xaxis"
        case .tax: return "doc.text.magnifyingglass"
        case .playbooks: return "book.closed"
        case .tags: return "tag"
        case .accounts: return "building.columns"
        case .connections: return "link"
        case .importCSV: return "square.and.arrow.down"
        case .backup: return "icloud"
        case .settings: return "gearshape"
        case .purchase: return "star.circle"
        }
    }

    struct Section: Identifiable {
        let title: String
        let items: [SidebarItem]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Journal", items: [.dashboard, .trades, .positions, .calendar]),
        Section(title: "Analyze", items: [.reports, .tax]),
        Section(title: "Library", items: [.playbooks, .tags, .accounts]),
        Section(title: "Data", items: [.connections, .importCSV, .backup]),
        Section(title: "App", items: [.settings, .purchase]),
    ]

    /// Items shown in the compact "More" tab.
    static let moreSections: [Section] = [
        Section(title: "Analyze", items: [.calendar, .tax]),
        Section(title: "Library", items: [.playbooks, .tags, .accounts]),
        Section(title: "Data", items: [.connections, .importCSV, .backup]),
        Section(title: "App", items: [.settings, .purchase]),
    ]
}
