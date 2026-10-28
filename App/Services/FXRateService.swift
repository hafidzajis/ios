import Foundation
import Observation
import SwiftData
import TradeLogCore
import TradeLogIntegrations

@MainActor
@Observable
final class FXRateService {
    var isFetching = false
    var progress: Double = 0
    var lastMessage: String?

    static func table(from rows: [FXRate]) -> FXRateTable {
        var rates: [String: Decimal] = [:]
        for row in rows where row.usdToMYR > 0 { rates[row.dayKey] = row.usdToMYR }
        return FXRateTable(rates: rates)
    }

    func table(context: ModelContext) -> FXRateTable {
        Self.table(from: (try? context.fetch(FetchDescriptor<FXRate>())) ?? [])
    }

    /// Ensures an FXRate row exists for each day, fetching the missing ones from BNM in small batches.
    @discardableResult
    func ensureRates(for days: Set<String>, context: ModelContext) async -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<FXRate>())) ?? []).map(\.dayKey))
        let missing = days.subtracting(existing).sorted()
        guard !missing.isEmpty else { return 0 }
        isFetching = true
        progress = 0
        lastMessage = nil
        defer { isFetching = false }

        let provider = BNMRateProvider()
        var fetched = 0
        let batchSize = 10
        var index = 0
        while index < missing.count {
            let batch = Set(missing[index ..< min(index + batchSize, missing.count)])
            let rates = await provider.rates(for: batch)
            for (day, rate) in rates {
                context.insert(FXRate(dayKey: day, usdToMYR: rate))
                fetched += 1
            }
            try? context.save()
            index += batchSize
            progress = Double(min(index, missing.count)) / Double(missing.count)
        }
        let stillMissing = missing.count - fetched
        lastMessage = stillMissing > 0
            ? "Fetched \(fetched) rates; \(stillMissing) days have no BNM rate. Enter them manually."
            : "Fetched \(fetched) rates."
        return fetched
    }

    func setManual(dayKey: String, rate: Decimal, context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
        if let row = rows.first(where: { $0.dayKey == dayKey }) {
            row.usdToMYR = rate
            row.isManual = true
            row.fetchedAt = Date()
        } else {
            context.insert(FXRate(dayKey: dayKey, usdToMYR: rate, isManual: true))
        }
        try? context.save()
    }

    /// Updates the display-currency rate (MYR per USD) from the newest cached row, or from BNM if the cache is empty.
    func refreshDisplayRate(settings: AppSettings, context: ModelContext) async {
        let rows = (try? context.fetch(FetchDescriptor<FXRate>())) ?? []
        if let latest = rows.max(by: { $0.dayKey < $1.dayKey }), latest.usdToMYR > 0,
           latest.dayKey >= FXRateTable.dayKey(for: Date().addingTimeInterval(-7 * 86_400)) {
            settings.displayRateMYR = latest.usdToMYR.doubleValue
            return
        }
        if let rate = try? await BNMRateProvider().usdToMYR(on: Date()), rate > 0 {
            settings.displayRateMYR = rate.doubleValue
        }
    }
}
