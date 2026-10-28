import Foundation
import SwiftData
import TradeLogCore

enum DateRange: String, CaseIterable, Identifiable {
    case d7 = "7D", d30 = "30D", d90 = "90D", ytd = "YTD", y1 = "1Y", all = "All"
    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .d7: return cal.date(byAdding: .day, value: -7, to: now)
        case .d30: return cal.date(byAdding: .day, value: -30, to: now)
        case .d90: return cal.date(byAdding: .day, value: -90, to: now)
        case .ytd: return cal.date(from: cal.dateComponents([.year], from: now))
        case .y1: return cal.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}

/// In-memory filtering (SwiftData predicates are limited for enums/optionals).
struct TradeFilter {
    var account: Account?
    var assetClass: AssetClass?
    var outcome: TradeOutcome?
    var setup: Setup?
    var tag: Tag?
    var range: DateRange = .all
    var search = ""
    var includeArchived = false

    var isActive: Bool {
        account != nil || assetClass != nil || outcome != nil || setup != nil || tag != nil || range != .all
    }

    mutating func reset() {
        account = nil; assetClass = nil; outcome = nil; setup = nil; tag = nil; range = .all
    }

    func apply(_ trades: [Trade]) -> [Trade] {
        let start = range.startDate
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return trades.filter { t in
            if !includeArchived && t.isArchived { return false }
            if let account, t.account?.persistentModelID != account.persistentModelID { return false }
            if let assetClass, t.assetClass != assetClass { return false }
            if let outcome, t.outcome != outcome { return false }
            if let setup, t.setup?.persistentModelID != setup.persistentModelID { return false }
            if let tag, !(t.tags ?? []).contains(where: { $0.persistentModelID == tag.persistentModelID }) { return false }
            if let start, t.sortDate < start { return false }
            if !query.isEmpty {
                let haystack = [t.symbol, t.notes, t.setup?.name ?? "", (t.tags ?? []).map(\.name).joined(separator: " ")]
                    .joined(separator: " ").lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }
}
