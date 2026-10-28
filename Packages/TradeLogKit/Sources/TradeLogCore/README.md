# TradeLogCore

Pure Foundation logic (builds on Linux and Apple platforms). All money values are `Decimal`.

| File | API |
|---|---|
| `Contracts.swift` | Shared types: `TradeInput`, `FillInput`, `TradeMetrics`, `ImportedExecution`, connector protocols |
| `TradeCalculator.swift` | `TradeCalculator.metrics(for:)`, `unrealizedPnL(for:metrics:currentPrice:)` |
| `PerformanceAnalyzer.swift` | `PerformanceAnalyzer.analyze(_:calendar:)` -> `PerformanceReport` (stats, equity curve, daily P&L, breakdowns by `BreakdownDimension`) |
| `TaxReport.swift` | Malaysia tax: `FXRateTable`, `TaxReportBuilder.requiredRateDays` / `.build` -> `TaxReport` (+ `csv()`). FIFO across all trades per symbol for spot/stocks, per-trade P&L for perps; days use Asia/Kuala_Lumpur |
| `CSV.swift` | `CSVWriter.write`, `CSVParser.parse` (RFC 4180) |
| `TradeAssembler.swift` | `TradeAssembler.assemble(_:)`: `ImportedExecution` -> `AssembledTrade` (flat-to-flat, splits flips, de-dupes, ignores non-USD fees) |
| `Formatting.swift` | `Decimal.doubleValue`, `Decimal.rounded(scale:)`, `MoneyFormat` |

Notes: only fully closed trades count in performance stats; missing FX rates convert to 0 and are listed in
`TaxReport.missingRateDays`; the report records and calculates, it does not decide taxability.
