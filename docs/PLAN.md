# TradeLog v1 — Plan

Trading journal for **US stocks and crypto** on **iPhone and iPad** (one SwiftUI codebase), with a
native **macOS** target planned later. Data lives on device (SwiftData) and syncs/backs up through the
user's own **iCloud** (CloudKit private database + JSON backup files). Monetisation target: a single
**one-time purchase** (StoreKit 2 non-consumable) once the product is complete; v1 ships all features
unlocked with the purchase plumbing in place.

## Features copied from the best journals

| Feature | Inspired by | v1 |
|---|---|---|
| Trade log with partial fills, fees, leverage, funding | TraderSync / TradeZella | Yes |
| Plan fields: entry, stop loss, take profit, target R:R, planned risk | All | Yes |
| R-multiple per trade | Tradervue / Edgewonk | Yes |
| Setups / playbooks with stats per setup | TradeZella | Yes |
| Indicator + free tags, emotion, "followed plan" | Edgewonk (Tiltmeter) | Yes |
| Chart screenshots per trade | All | Yes |
| Dashboard: win rate, profit factor, expectancy, max drawdown, equity curve | All | Yes |
| P&L calendar heatmap | TradeZella | Yes |
| Breakdowns by setup / tag / symbol / weekday / hour / asset class | Tradervue | Yes |
| Broker/exchange API sync (read-only) | TraderSync | Yes (see below) |
| CSV import | All | Yes (generic mapping) |
| Live prices for open positions | TraderSync | Yes |
| Malaysia tax report (MYR, FIFO, BNM rates) | none — our differentiator | Yes |
| Trade replay, AI coach | TradeZella / TraderSync | Later |

## Architecture

```
App/                         SwiftUI app (iOS/iPadOS 17+; macOS later)
  TradeLogApp.swift          ModelContainer with CloudKit
  Models/                    SwiftData @Model types (CloudKit-safe)
  Features/…                 Trades, Positions, Dashboard, Reports, Tax, Connections, Settings
  Services/                  Keychain, sync coordinator, backup, PDF export, store
Packages/TradeLogKit/
  TradeLogCore               Pure logic, Linux-buildable: metrics, stats, FIFO tax, CSV
  TradeLogIntegrations       API connectors, price + FX providers, CSV import
project.yml                  XcodeGen spec → TradeLog.xcodeproj
```

Rules:
- `TradeLogCore` is Foundation-only and has unit tests; all P&L/tax math lives there, never in views.
- The app converts SwiftData models → `TradeInput` snapshots and calls Core.
- CloudKit constraints on SwiftData: every attribute has a default or is optional, all relationships
  optional, no `@Attribute(.unique)`, no `.deny` delete rules.
- API keys are stored only in the Keychain (`kSecAttrSynchronizable` = true so they follow iCloud
  Keychain), never in SwiftData/CloudKit or backups.
- Navigation is `NavigationSplitView`, so iPhone gets a stack, iPad / foldable iPhone / Mac get columns.

## Integrations (read-only)

| Service | Data | Auth |
|---|---|---|
| Binance | Spot trades (`/api/v3/myTrades`), USDⓈ-M futures (`/fapi/v1/userTrades`) | API key + HMAC-SHA256 |
| Bybit | V5 executions (`/v5/execution/list`, spot + linear) | API key + HMAC-SHA256 |
| Alpaca | Fill activities (`/v2/account/activities/FILL`) | Key ID + secret headers |
| Interactive Brokers | Flex Web Service trade report (XML) | Flex token + query ID |
| CSV | Any broker (e.g. Moomoo, Webull, Coinbase) via column mapping | — |
| CoinGecko / Binance public | Crypto prices | none |
| Finnhub | US stock quotes | free API key |
| Bank Negara Malaysia API | USD→MYR daily rate for tax | none |

## Tax report (Malaysia) — what the app does

- Year of assessment = calendar year.
- Spot crypto and US stocks: FIFO lot matching across all trades of the same symbol; cost and
  proceeds converted to MYR at the BNM rate of each fill date.
- Perps: realised net P&L per closed trade converted at the close date.
- Output: disposal table + yearly summary (gains, losses, fees, net) → PDF and CSV.
- The app records and calculates; it does not decide taxability (LHDN "badges of trade"). A
  disclaimer is shown on the report.

## One-time purchase (prepared, not enforced in v1)

- Product: `com.hafidzajis.tradelog.lifetime` (non-consumable), StoreKit configuration file for testing.
- `PurchaseManager` exposes `isUnlocked`; v1 sets a debug override so nothing is gated.

## Milestones

1. v1 (this branch): everything in the tables above marked "Yes".
2. macOS target (add `macOS` to `supportedDestinations`, Mac-specific menus/commands).
3. Turn on purchase gating, App Store assets, privacy manifest review.
4. Trade replay, more connectors (Coinbase Advanced JWT, OKX, Tiger/Moomoo OpenAPI).
