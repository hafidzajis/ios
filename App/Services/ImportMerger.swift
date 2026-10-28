import Foundation
import SwiftData
import TradeLogCore

struct ImportResult: Equatable {
    var executionsReceived = 0
    var duplicatesSkipped = 0
    var tradesCreated = 0
    var tradesUpdated = 0

    var executionsImported: Int { executionsReceived - duplicatesSkipped }
}

/// Shared merge path for API sync and CSV import.
@MainActor
enum ImportMerger {
    static func merge(executions: [ImportedExecution], account: Account?, context: ModelContext) throws -> ImportResult {
        var result = ImportResult()
        result.executionsReceived = executions.count

        // 1. Drop executions that already exist on a Fill.
        let existingFills = try context.fetch(FetchDescriptor<Fill>())
        var knownIDs = Set<String>()
        for fill in existingFills { knownIDs.formUnion(fill.externalIDs) }
        let fresh = executions.filter { !knownIDs.contains($0.id) }
        result.duplicatesSkipped = executions.count - fresh.count
        guard !fresh.isEmpty else { return result }

        // 2. Assemble into trades.
        let assembled = TradeAssembler.assemble(fresh)
        let allTrades = try context.fetch(FetchDescriptor<Trade>())
        var touched: [Trade] = []

        for item in assembled {
            let fills = makeFills(for: item)
            let existing = allTrades.first { t in
                t.isOpen && !t.isArchived
                    && t.symbol == item.symbol
                    && t.assetClass == item.assetClass
                    && t.side == item.side
                    && t.account?.persistentModelID == account?.persistentModelID
            }
            if let trade = existing {
                for f in fills {
                    context.insert(f)
                    trade.addFill(f)
                }
                trade.updatedAt = Date()
                if !touched.contains(where: { $0 === trade }) {
                    touched.append(trade)
                    result.tradesUpdated += 1
                }
            } else {
                let trade = Trade(symbol: item.symbol, assetClass: item.assetClass, side: item.side, account: account)
                context.insert(trade)
                for f in fills {
                    context.insert(f)
                    trade.addFill(f)
                }
                touched.append(trade)
                result.tradesCreated += 1
            }
        }

        for trade in touched { trade.refreshCache() }
        try context.save()
        return result
    }

    /// Builds Fill models. `executionIDs` are matched to fills by index when counts agree; otherwise all ids
    /// are attached (joined by "|") to the first fill so de-duplication still works.
    private static func makeFills(for item: AssembledTrade) -> [Fill] {
        let normalized = item.executionIDs.map { id in
            id.hasPrefix(item.source + ":") ? id : item.source + ":" + id
        }
        let aligned = normalized.count == item.fills.count
        return item.fills.enumerated().map { index, f in
            let ext: String?
            if aligned {
                ext = normalized[index]
            } else if index == 0 {
                ext = normalized.joined(separator: "|")
            } else {
                ext = nil
            }
            return Fill(uuid: UUID(), action: f.action, date: f.date, price: f.price, quantity: f.quantity, fee: f.fee, externalID: ext)
        }
    }
}
