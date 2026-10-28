import Foundation
import SwiftData

/// First-launch seeding and code-level de-duplication (SwiftData + CloudKit cannot enforce unique attributes).
@MainActor
enum SeedData {
    static let indicators = [
        "RSI", "MACD", "EMA 20", "EMA 50", "EMA 200", "VWAP", "Bollinger Bands", "Volume",
        "Support/Resistance", "Fibonacci", "Ichimoku", "Stochastic",
    ]

    static func run(context: ModelContext, settings: AppSettings) {
        dedupeTags(context: context)
        dedupeFXRates(context: context)
        if !settings.tagsSeeded {
            let existing = Set(((try? context.fetch(FetchDescriptor<Tag>())) ?? []).map { $0.name.lowercased() })
            for name in indicators where !existing.contains(name.lowercased()) {
                context.insert(Tag(name: name, kind: .indicator, colorHex: "#5E5CE6"))
            }
            for name in ["Overtraded", "Moved stop", "Chased entry", "No stop loss"]
            where !existing.contains(name.lowercased()) {
                context.insert(Tag(name: name, kind: .mistake, colorHex: "#FF453A"))
            }
            settings.tagsSeeded = true
        }
        try? context.save()
    }

    static func dedupeTags(context: ModelContext) {
        guard let tags = try? context.fetch(FetchDescriptor<Tag>()) else { return }
        var keep: [String: Tag] = [:]
        for tag in tags.sorted(by: { $0.name < $1.name }) {
            let key = tag.kindRaw + "|" + tag.name.lowercased()
            if let survivor = keep[key] {
                for trade in tag.trades ?? [] {
                    if !(trade.tags ?? []).contains(where: { $0 === survivor }) {
                        trade.tags = (trade.tags ?? []) + [survivor]
                    }
                    trade.tags?.removeAll { $0 === tag }
                }
                context.delete(tag)
            } else {
                keep[key] = tag
            }
        }
    }

    static func dedupeFXRates(context: ModelContext) {
        guard let rows = try? context.fetch(FetchDescriptor<FXRate>()) else { return }
        var seen: [String: FXRate] = [:]
        for row in rows.sorted(by: { $0.fetchedAt > $1.fetchedAt }) {
            if let existing = seen[row.dayKey] {
                // Keep a manual rate over a fetched one, otherwise the most recent.
                if row.isManual && !existing.isManual {
                    context.delete(existing)
                    seen[row.dayKey] = row
                } else {
                    context.delete(row)
                }
            } else {
                seen[row.dayKey] = row
            }
        }
    }
}
