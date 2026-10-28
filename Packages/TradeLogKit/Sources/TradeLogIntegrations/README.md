# TradeLogIntegrations

Read-only connectors, price/FX providers and CSV import for TradeLog. No connector can place orders
or move funds: always create keys with the minimum (read-only) permission. Keys are stored by the
app in the Keychain, never in this module.

## Connectors

| ID | Credentials (`CredentialField.key`) | Data |
|---|---|---|
| `binance` | `apiKey`, `apiSecret`, `symbols` (e.g. `BTCUSDT,ETHUSDT`), `includeFutures` (`true`/`false`) | Spot `myTrades`, USDⓈ-M `userTrades` |
| `bybit` | `apiKey`, `apiSecret` | V5 executions, spot + linear |
| `alpaca` | `keyID`, `secretKey`, `environment` (`live`/`paper`) | FILL activities |
| `ibkr` | `token`, `queryID` | Flex Web Service trade report |

### Getting read-only keys

- **Binance**: Account -> API Management -> Create API. In the key's restrictions enable **only
  "Enable Reading"** (leave Spot/Margin trading, Futures, Withdrawals unchecked). Optionally restrict
  by IP. Binance requires one symbol per request, so list the pairs you trade in `symbols`; tick
  `includeFutures` only if the key may also read your USDⓈ-M Futures account.
- **Bybit**: Profile -> API -> Create New Key -> System-generated, permission **Read-Only**; under
  "Unified Trading" tick *Orders* and *Trade* read access only (Read-Only mode hides write options).
- **Alpaca**: Dashboard -> API Keys -> Generate. Use the *Paper* dashboard for paper keys (set
  `environment` to `paper`). Alpaca keys are not scope-limited; the app only issues GET requests.
- **Interactive Brokers**: Client Portal -> Performance & Reports -> Flex Queries ->
  create an **Activity Flex Query** (or Trade Confirmation) with the **Trades** section, level of
  detail **Execution**, fields at least `Symbol, AssetClass, TradeID, IBOrderID, DateTime (or
  TradeDate+TradeTime), Buy/Sell, Quantity, TradePrice, IBCommission, IBCommissionCurrency, Currency`,
  format **XML**, period e.g. Last 365 Days. Note the **Query ID**. Then Flex Web Service
  Configuration (same page, gear icon) -> enable it and generate a **token**.

### Behaviour notes

- Binance `externalID` is `SYMBOL-id` (spot) / `F-SYMBOL-id` (futures) because ids repeat across
  symbols. Futures history is limited to ~6 months and 7-day request windows; Bybit executions are
  limited to 7-day windows and 2 years. `since` is chunked automatically.
- Exchange fees are reported in the fee asset (`feeCurrency`) and are not converted.
- Alpaca regulatory/crypto fees are separate non-FILL activities and are not imported (fee = 0).
- IBKR times are in the account timezone; America/New_York is assumed. Only STK and CRYPTO rows are
  imported.
- Money is parsed from the exchange's JSON strings with `Decimal(string:)`. Public price APIs that
  send JSON numbers (CoinGecko, Finnhub, BNM) are converted through the Double's shortest text.

## Prices and FX

- `CoinGeckoPriceProvider` (keyless), `BinancePublicPriceProvider` (keyless, spot + perp),
  `FinnhubPriceProvider(apiKey:)` (free key), `CompositePriceProvider` (stocks -> Finnhub, crypto ->
  Binance public with CoinGecko fallback).
- `BNMRateProvider` (actor): USD/MYR middle rate from Bank Negara Malaysia, cached per Kuala Lumpur
  day, walks back up to 7 days over weekends/holidays; `rates(for:)` batches by month.

## CSV

`CSVExecutionImporter.headers(in:)` -> `guessMapping(headers:defaultAssetClass:)` -> user adjusts the
`CSVColumnMapping` -> `parse(_:mapping:source:)`. Handles `$`/thousand separators, negative
quantities, buy/sell wording, `EST`/`PST` suffixes, ISO8601 / epoch / common US formats or a custom
`dateFormat`. Missing ids become a stable FNV-1a hash of the row.

## Cross-platform

Linux builds use `FoundationNetworking`, `FoundationXML` and swift-crypto (`import Crypto`); Apple
platforms use CryptoKit. The HMAC helper is called `HMACSigner` to avoid clashing with `HMAC<H>`.
