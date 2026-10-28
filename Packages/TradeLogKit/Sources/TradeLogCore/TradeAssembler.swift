import Foundation

public struct AssembledTrade: Sendable, Hashable {
    public var symbol: String
    public var assetClass: AssetClass
    public var side: TradeSide
    public var fills: [FillInput]
    public var executionIDs: [String]
    public var isOpen: Bool
    public var source: String

    public init(symbol: String, assetClass: AssetClass, side: TradeSide, fills: [FillInput],
                executionIDs: [String], isOpen: Bool, source: String) {
        self.symbol = symbol
        self.assetClass = assetClass
        self.side = side
        self.fills = fills
        self.executionIDs = executionIDs
        self.isOpen = isOpen
        self.source = source
    }
}

/// Groups imported executions into trades.
///
/// Per (source, assetClass, symbol) the executions are replayed chronologically from a flat position.
/// The first execution sets the side; same-direction executions are open fills, opposite ones are close
/// fills. When the position returns to exactly zero the trade is closed. An execution that flips through
/// zero is split into a closing fill and an opening fill of a new trade (fee split pro-rata).
///
/// Fees: `execution.fee` is used only when `feeCurrency` is nil or a USD-like stable coin
/// (USD, USDT, USDC, BUSD, FDUSD). Fees paid in other currencies (e.g. base coin) are ignored (0) in v1.
///
/// `executionIDs` hold `ImportedExecution.id` ("source:externalID"). Executions with the same id are
/// counted once.
public enum TradeAssembler {
    private static let usdLikeCurrencies: Set<String> = ["USD", "USDT", "USDC", "BUSD", "FDUSD"]

    private struct Builder {
        var side: TradeSide
        var fills: [FillInput] = []
        var executionIDs: [String] = []
    }

    public static func assemble(_ executions: [ImportedExecution]) -> [AssembledTrade] {
        // De-duplicate by id, keeping first occurrence and input order.
        var seen = Set<String>()
        var unique: [ImportedExecution] = []
        for execution in executions {
            if seen.insert(execution.id).inserted && execution.quantity > 0 {
                unique.append(execution)
            }
        }

        // Group.
        var groups: [String: [(index: Int, execution: ImportedExecution)]] = [:]
        for (index, execution) in unique.enumerated() {
            let key = "\(execution.source)|\(execution.assetClass.rawValue)|\(execution.symbol)"
            groups[key, default: []].append((index: index, execution: execution))
        }

        var result: [AssembledTrade] = []
        for key in groups.keys.sorted() {
            guard let group = groups[key], let first = group.first else { continue }
            let sorted = group.sorted { a, b in
                if a.execution.date != b.execution.date { return a.execution.date < b.execution.date }
                return a.index < b.index
            }
            let source = first.execution.source
            let symbol = first.execution.symbol
            let assetClass = first.execution.assetClass

            func finish(_ builder: Builder, isOpen: Bool) {
                result.append(AssembledTrade(
                    symbol: symbol, assetClass: assetClass, side: builder.side, fills: builder.fills,
                    executionIDs: builder.executionIDs, isOpen: isOpen, source: source
                ))
            }

            var current: Builder?
            var position = Decimal(0) // signed: long positive, short negative

            for entry in sorted {
                let execution = entry.execution
                let fee = usableFee(execution)
                let qty = execution.quantity
                let signedQty: Decimal = execution.side == .buy ? qty : -qty

                guard var builder = current else {
                    var fresh = Builder(side: execution.side == .buy ? .long : .short)
                    fresh.fills.append(FillInput(action: .open, date: execution.date, price: execution.price,
                                                 quantity: qty, fee: fee))
                    fresh.executionIDs.append(execution.id)
                    current = fresh
                    position = signedQty
                    continue
                }

                if signedQty * position > 0 {
                    // Same direction: add to the position.
                    builder.fills.append(FillInput(action: .open, date: execution.date, price: execution.price,
                                                   quantity: qty, fee: fee))
                    builder.executionIDs.append(execution.id)
                    position += signedQty
                    current = builder
                    continue
                }

                let absPosition: Decimal = position < 0 ? -position : position
                if qty <= absPosition {
                    builder.fills.append(FillInput(action: .close, date: execution.date, price: execution.price,
                                                   quantity: qty, fee: fee))
                    builder.executionIDs.append(execution.id)
                    position += signedQty
                    if position == 0 {
                        finish(builder, isOpen: false)
                        current = nil
                    } else {
                        current = builder
                    }
                } else {
                    // Flip through zero: close the old trade, open a new one with the remainder.
                    let closeQty = absPosition
                    let remainder = qty - closeQty
                    let closeFee = fee * closeQty / qty
                    let openFee = fee - closeFee
                    builder.fills.append(FillInput(action: .close, date: execution.date, price: execution.price,
                                                   quantity: closeQty, fee: closeFee))
                    builder.executionIDs.append(execution.id)
                    finish(builder, isOpen: false)

                    var fresh = Builder(side: execution.side == .buy ? .long : .short)
                    fresh.fills.append(FillInput(action: .open, date: execution.date, price: execution.price,
                                                 quantity: remainder, fee: openFee))
                    fresh.executionIDs.append(execution.id)
                    current = fresh
                    position = execution.side == .buy ? remainder : -remainder
                }
            }

            if let builder = current {
                finish(builder, isOpen: true)
            }
        }

        result.sort { a, b in
            let da = a.fills.first?.date ?? Date.distantPast
            let db = b.fills.first?.date ?? Date.distantPast
            if da != db { return da < db }
            return a.symbol < b.symbol
        }
        return result
    }

    private static func usableFee(_ execution: ImportedExecution) -> Decimal {
        guard let currency = execution.feeCurrency else { return execution.fee }
        if usdLikeCurrencies.contains(currency.uppercased()) { return execution.fee }
        return 0
    }
}
