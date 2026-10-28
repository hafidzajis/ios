import Foundation

// MARK: - FX table

public struct FXRateTable: Codable, Sendable {
    /// MYR per 1 USD, keyed by yyyy-MM-dd in Asia/Kuala_Lumpur.
    public var rates: [String: Decimal]

    public init(rates: [String: Decimal]) {
        self.rates = rates
    }

    /// Rate for the exact day, or the latest earlier day within 7 days.
    public func rate(on date: Date) -> Decimal? {
        let calendar = FXRateTable.makeCalendar()
        for offset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            if let value = rates[FXRateTable.dayKey(for: candidate)] {
                return value
            }
        }
        return nil
    }

    public static func dayKey(for date: Date) -> String {
        let calendar = makeCalendar()
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let y = parts.year ?? 0
        let m = parts.month ?? 0
        let d = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur") ?? TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
        return calendar
    }
}

// MARK: - Types

public enum TaxMethod: String, Codable, Sendable {
    case fifo
    case derivativePnL
}

public struct TaxDisposal: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var symbol: String
    public var assetClass: AssetClass
    /// long = bought then sold; short = sold then bought back.
    public var side: TradeSide
    public var quantity: Decimal
    public var acquiredDate: Date
    public var disposedDate: Date
    public var costUSD: Decimal
    public var proceedsUSD: Decimal
    public var feesUSD: Decimal
    public var costMYR: Decimal
    public var proceedsMYR: Decimal
    public var feesMYR: Decimal
    public var gainMYR: Decimal // proceeds - cost - fees
    public var method: TaxMethod
    public var fxRateAtAcquire: Decimal?
    public var fxRateAtDispose: Decimal?

    public init(
        id: UUID = UUID(), symbol: String, assetClass: AssetClass, side: TradeSide, quantity: Decimal,
        acquiredDate: Date, disposedDate: Date, costUSD: Decimal, proceedsUSD: Decimal, feesUSD: Decimal,
        costMYR: Decimal, proceedsMYR: Decimal, feesMYR: Decimal, gainMYR: Decimal, method: TaxMethod,
        fxRateAtAcquire: Decimal?, fxRateAtDispose: Decimal?
    ) {
        self.id = id
        self.symbol = symbol
        self.assetClass = assetClass
        self.side = side
        self.quantity = quantity
        self.acquiredDate = acquiredDate
        self.disposedDate = disposedDate
        self.costUSD = costUSD
        self.proceedsUSD = proceedsUSD
        self.feesUSD = feesUSD
        self.costMYR = costMYR
        self.proceedsMYR = proceedsMYR
        self.feesMYR = feesMYR
        self.gainMYR = gainMYR
        self.method = method
        self.fxRateAtAcquire = fxRateAtAcquire
        self.fxRateAtDispose = fxRateAtDispose
    }
}

public struct TaxLot: Codable, Sendable, Hashable {
    public var symbol: String
    public var assetClass: AssetClass
    public var side: TradeSide
    public var quantity: Decimal
    public var unitCostUSD: Decimal
    public var feePerUnitUSD: Decimal
    public var acquiredDate: Date

    public init(symbol: String, assetClass: AssetClass, side: TradeSide, quantity: Decimal,
                unitCostUSD: Decimal, feePerUnitUSD: Decimal, acquiredDate: Date) {
        self.symbol = symbol
        self.assetClass = assetClass
        self.side = side
        self.quantity = quantity
        self.unitCostUSD = unitCostUSD
        self.feePerUnitUSD = feePerUnitUSD
        self.acquiredDate = acquiredDate
    }
}

public struct TaxSummaryRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String { assetClass.rawValue }
    public var assetClass: AssetClass
    public var disposals: Int
    public var proceedsMYR: Decimal
    public var costMYR: Decimal
    public var feesMYR: Decimal
    public var gainsMYR: Decimal // sum of positive gains
    public var lossesMYR: Decimal // sum of losses, as a positive number
    public var netMYR: Decimal

    public init(assetClass: AssetClass, disposals: Int, proceedsMYR: Decimal, costMYR: Decimal, feesMYR: Decimal,
                gainsMYR: Decimal, lossesMYR: Decimal, netMYR: Decimal) {
        self.assetClass = assetClass
        self.disposals = disposals
        self.proceedsMYR = proceedsMYR
        self.costMYR = costMYR
        self.feesMYR = feesMYR
        self.gainsMYR = gainsMYR
        self.lossesMYR = lossesMYR
        self.netMYR = netMYR
    }
}

public struct TaxReport: Codable, Sendable {
    public var year: Int
    public var disposals: [TaxDisposal]
    public var summary: [TaxSummaryRow]
    public var totalNetMYR: Decimal
    public var openLotsAtYearEnd: [TaxLot]
    public var missingRateDays: [String]
    public var generatedAt: Date

    public init(year: Int, disposals: [TaxDisposal], summary: [TaxSummaryRow], totalNetMYR: Decimal,
                openLotsAtYearEnd: [TaxLot], missingRateDays: [String], generatedAt: Date) {
        self.year = year
        self.disposals = disposals
        self.summary = summary
        self.totalNetMYR = totalNetMYR
        self.openLotsAtYearEnd = openLotsAtYearEnd
        self.missingRateDays = missingRateDays
        self.generatedAt = generatedAt
    }

    /// CSV with a header row, one row per disposal, then summary rows.
    public func csv() -> String {
        var rows: [[String]] = []
        rows.append([
            "Year", "Symbol", "Asset Class", "Method", "Side", "Quantity", "Acquired Date", "Disposed Date",
            "Cost (USD)", "Proceeds (USD)", "Fees (USD)", "FX Acquire (MYR/USD)", "FX Dispose (MYR/USD)",
            "Cost (MYR)", "Proceeds (MYR)", "Fees (MYR)", "Gain/Loss (MYR)",
        ])
        for d in disposals {
            rows.append([
                String(year), d.symbol, d.assetClass.displayName, d.method.rawValue, d.side.rawValue,
                "\(d.quantity)", FXRateTable.dayKey(for: d.acquiredDate), FXRateTable.dayKey(for: d.disposedDate),
                "\(d.costUSD)", "\(d.proceedsUSD)", "\(d.feesUSD)",
                d.fxRateAtAcquire.map { "\($0)" } ?? "", d.fxRateAtDispose.map { "\($0)" } ?? "",
                "\(d.costMYR)", "\(d.proceedsMYR)", "\(d.feesMYR)", "\(d.gainMYR)",
            ])
        }
        rows.append([])
        rows.append(["SUMMARY", "Asset Class", "Disposals", "Proceeds (MYR)", "Cost (MYR)", "Fees (MYR)",
                     "Gains (MYR)", "Losses (MYR)", "Net (MYR)"])
        for s in summary {
            rows.append(["SUMMARY", s.assetClass.displayName, String(s.disposals), "\(s.proceedsMYR)", "\(s.costMYR)",
                         "\(s.feesMYR)", "\(s.gainsMYR)", "\(s.lossesMYR)", "\(s.netMYR)"])
        }
        rows.append(["TOTAL", "", "", "", "", "", "", "", "\(totalNetMYR)"])
        return CSVWriter.write(rows)
    }
}

// MARK: - Builder

public enum TaxReportBuilder {
    private struct Event {
        var index: Int
        var date: Date
        var isBuy: Bool
        var price: Decimal
        var quantity: Decimal
        var fee: Decimal
    }

    private struct Lot {
        var side: TradeSide
        var quantity: Decimal
        var unitPrice: Decimal
        var feePerUnit: Decimal
        var date: Date
    }

    private struct RateContext {
        var table: FXRateTable
        var missing = Set<String>()

        /// Converts a USD amount at the day's rate; returns (MYR, rate). Missing rate converts to 0.
        mutating func convert(_ usd: Decimal, on date: Date) -> (myr: Decimal, rate: Decimal?) {
            if let rate = table.rate(on: date) {
                return (usd * rate, rate)
            }
            missing.insert(FXRateTable.dayKey(for: date))
            return (0, nil)
        }
    }

    /// Fill days (yyyy-MM-dd, Kuala Lumpur) of all fills up to the end of `year`. This covers the disposal
    /// days and the acquisition days of every lot that could be disposed in that year.
    public static func requiredRateDays(trades: [TradeInput], year: Int) -> Set<String> {
        let calendar = FXRateTable.makeCalendar()
        var days = Set<String>()
        for trade in trades {
            for fill in trade.fills {
                if calendar.component(.year, from: fill.date) <= year {
                    days.insert(FXRateTable.dayKey(for: fill.date))
                }
            }
        }
        return days
    }

    public static func build(trades: [TradeInput], year: Int, rates: FXRateTable, now: Date = Date()) -> TaxReport {
        let calendar = FXRateTable.makeCalendar()
        var context = RateContext(table: rates)
        var disposals: [TaxDisposal] = []
        var openLots: [TaxLot] = []

        // FIFO for spot assets: pool all fills per (assetClass, symbol).
        var pools: [String: [Event]] = [:]
        var poolInfo: [String: (symbol: String, assetClass: AssetClass)] = [:]
        var counter = 0
        for trade in trades where trade.assetClass != .cryptoPerp {
            let key = "\(trade.assetClass.rawValue)|\(trade.symbol)"
            poolInfo[key] = (symbol: trade.symbol, assetClass: trade.assetClass)
            for fill in trade.fills where fill.quantity > 0 {
                let isBuy = (trade.side == .long && fill.action == .open) || (trade.side == .short && fill.action == .close)
                pools[key, default: []].append(Event(index: counter, date: fill.date, isBuy: isBuy,
                                                     price: fill.price, quantity: fill.quantity, fee: fill.fee))
                counter += 1
            }
        }

        for key in pools.keys.sorted() {
            guard let info = poolInfo[key], let unsorted = pools[key] else { continue }
            let events = unsorted.sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.index < b.index
            }
            var lots: [Lot] = []

            for event in events {
                if calendar.component(.year, from: event.date) > year { break }
                let inYear = calendar.component(.year, from: event.date) == year
                let unitFee = event.fee / event.quantity
                var remaining = event.quantity
                let closingSide: TradeSide = event.isBuy ? .short : .long

                while remaining > 0, let lotIndex = lots.firstIndex(where: { $0.side == closingSide }) {
                    var lot = lots[lotIndex]
                    let matched = remaining < lot.quantity ? remaining : lot.quantity
                    if inYear {
                        let disposal = makeDisposal(
                            info: info, lot: lot, matched: matched, closeDate: event.date,
                            closePrice: event.price, closeUnitFee: unitFee, context: &context
                        )
                        disposals.append(disposal)
                    }
                    lot.quantity -= matched
                    remaining -= matched
                    if lot.quantity > 0 {
                        lots[lotIndex] = lot
                    } else {
                        lots.remove(at: lotIndex)
                    }
                }

                if remaining > 0 {
                    lots.append(Lot(side: event.isBuy ? .long : .short, quantity: remaining,
                                    unitPrice: event.price, feePerUnit: unitFee, date: event.date))
                }
            }

            for lot in lots {
                openLots.append(TaxLot(symbol: info.symbol, assetClass: info.assetClass, side: lot.side,
                                       quantity: lot.quantity, unitCostUSD: lot.unitPrice,
                                       feePerUnitUSD: lot.feePerUnit, acquiredDate: lot.date))
            }
        }

        // Perps: one disposal per fully closed trade, closed in `year`.
        for trade in trades where trade.assetClass == .cryptoPerp {
            let metrics = TradeCalculator.metrics(for: trade)
            guard metrics.outcome != .open, let closeDate = metrics.closeDate,
                  let openDate = metrics.openDate, let entry = metrics.avgEntryPrice else { continue }
            if calendar.component(.year, from: closeDate) != year { continue }
            let quantity = metrics.closedQuantity
            let costUSD = entry * quantity
            let proceedsUSD = costUSD + metrics.grossRealizedPnL
            let feesUSD = metrics.totalFees + trade.fundingFees
            let cost = context.convert(costUSD, on: closeDate)
            let proceeds = context.convert(proceedsUSD, on: closeDate)
            let fees = context.convert(feesUSD, on: closeDate)
            disposals.append(TaxDisposal(
                symbol: trade.symbol, assetClass: .cryptoPerp, side: trade.side, quantity: quantity,
                acquiredDate: openDate, disposedDate: closeDate, costUSD: costUSD, proceedsUSD: proceedsUSD,
                feesUSD: feesUSD, costMYR: cost.myr, proceedsMYR: proceeds.myr, feesMYR: fees.myr,
                gainMYR: proceeds.myr - cost.myr - fees.myr, method: .derivativePnL,
                fxRateAtAcquire: nil, fxRateAtDispose: cost.rate
            ))
        }

        disposals.sort { a, b in
            if a.disposedDate != b.disposedDate { return a.disposedDate < b.disposedDate }
            return a.symbol < b.symbol
        }

        var summary: [TaxSummaryRow] = []
        for assetClass in AssetClass.allCases {
            let subset = disposals.filter { $0.assetClass == assetClass }
            if subset.isEmpty { continue }
            var proceeds = Decimal(0)
            var cost = Decimal(0)
            var fees = Decimal(0)
            var gains = Decimal(0)
            var losses = Decimal(0)
            var net = Decimal(0)
            for d in subset {
                proceeds += d.proceedsMYR
                cost += d.costMYR
                fees += d.feesMYR
                net += d.gainMYR
                if d.gainMYR > 0 {
                    gains += d.gainMYR
                } else if d.gainMYR < 0 {
                    losses += -d.gainMYR
                }
            }
            summary.append(TaxSummaryRow(assetClass: assetClass, disposals: subset.count, proceedsMYR: proceeds,
                                         costMYR: cost, feesMYR: fees, gainsMYR: gains, lossesMYR: losses,
                                         netMYR: net))
        }
        let totalNet = summary.reduce(Decimal(0)) { $0 + $1.netMYR }

        return TaxReport(year: year, disposals: disposals, summary: summary, totalNetMYR: totalNet,
                         openLotsAtYearEnd: openLots, missingRateDays: context.missing.sorted(), generatedAt: now)
    }

    private static func makeDisposal(
        info: (symbol: String, assetClass: AssetClass), lot: Lot, matched: Decimal, closeDate: Date,
        closePrice: Decimal, closeUnitFee: Decimal, context: inout RateContext
    ) -> TaxDisposal {
        let lotFeeUSD = lot.feePerUnit * matched
        let closeFeeUSD = closeUnitFee * matched
        let feesUSD = lotFeeUSD + closeFeeUSD
        let lotValueUSD = lot.unitPrice * matched
        let closeValueUSD = closePrice * matched

        let costUSD: Decimal
        let proceedsUSD: Decimal
        let costMYR: Decimal
        let proceedsMYR: Decimal

        let lotLeg = context.convert(lotValueUSD, on: lot.date)
        let closeLeg = context.convert(closeValueUSD, on: closeDate)
        if lot.side == .long {
            // Bought (lot) then sold (close).
            costUSD = lotValueUSD
            proceedsUSD = closeValueUSD
            costMYR = lotLeg.myr
            proceedsMYR = closeLeg.myr
        } else {
            // Sold (lot) then bought back (close).
            costUSD = closeValueUSD
            proceedsUSD = lotValueUSD
            costMYR = closeLeg.myr
            proceedsMYR = lotLeg.myr
        }
        let acquireRate = lotLeg.rate
        let disposeRate = closeLeg.rate

        let lotFeeLeg = context.convert(lotFeeUSD, on: lot.date)
        let closeFeeLeg = context.convert(closeFeeUSD, on: closeDate)
        let feesMYR = lotFeeLeg.myr + closeFeeLeg.myr

        return TaxDisposal(
            symbol: info.symbol, assetClass: info.assetClass, side: lot.side, quantity: matched,
            acquiredDate: lot.date, disposedDate: closeDate, costUSD: costUSD, proceedsUSD: proceedsUSD,
            feesUSD: feesUSD, costMYR: costMYR, proceedsMYR: proceedsMYR, feesMYR: feesMYR,
            gainMYR: proceedsMYR - costMYR - feesMYR, method: .fifo,
            fxRateAtAcquire: acquireRate, fxRateAtDispose: disposeRate
        )
    }
}
