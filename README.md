# TradeLog

A trading journal for **US stocks and crypto** on **iPhone and iPad** (one SwiftUI codebase; a macOS target is planned).
Data lives on device in SwiftData and syncs through your own iCloud (CloudKit private database), with JSON
backups in iCloud Drive. Includes a **Malaysia tax report** (MYR, FIFO, Bank Negara Malaysia rates).

## What it does

- Trade log with partial fills, fees, leverage and funding, R multiples, plan vs actual
- Setups (playbooks), indicator / custom / mistake tags, emotions, "followed plan", chart screenshots
- Dashboard (win rate, profit factor, expectancy, max drawdown, equity curve), P&L calendar heatmap,
  breakdowns by setup / tag / symbol / weekday / hour / asset class, R-multiple distribution
- Open positions with live prices (Binance / CoinGecko for crypto, Finnhub for US stocks)
- Read-only API sync (Binance, Bybit, Alpaca, Interactive Brokers Flex) and generic CSV import
- Malaysia tax report per year of assessment: FIFO disposals, BNM USD/MYR rates, PDF and CSV export
- Backup and restore (JSON, replace or merge), automatic daily backup, one-time purchase plumbing (StoreKit 2)

See `docs/PLAN.md` for the full plan and architecture.

## Requirements

- Xcode 16 or newer, iOS 17+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

```sh
brew install xcodegen
xcodegen generate        # creates TradeLog.xcodeproj from project.yml (the project file is git-ignored)
open TradeLog.xcodeproj
```

Select the `TradeLog` scheme. The scheme already points at `App/Resources/TradeLog.storekit`, so the
purchase flow works in the simulator without App Store Connect.

## Signing and iCloud setup

1. In Xcode, select the `TradeLog` target, Signing & Capabilities, and choose your Team
   (or set `DEVELOPMENT_TEAM` in `project.yml`). Change the bundle id prefix if `com.hafidzajis` is not yours.
2. Capabilities (the entitlements file is already in `App/TradeLog.entitlements`):
   - **iCloud** with **CloudKit** and **iCloud Documents** checked
   - Create/select the container `iCloud.com.hafidzajis.tradelog` (update it in the entitlements,
     `App/TradeLogApp.swift` and `App/Services/BackupService.swift` if you use another id)
   - **Push Notifications** (CloudKit uses silent pushes) and **Background Modes > Remote notifications**
   - **Keychain Sharing** group `com.hafidzajis.tradelog` (API keys sync through iCloud Keychain)
3. In the CloudKit Dashboard, deploy the development schema to production before shipping to TestFlight/App Store.
4. If the CloudKit store cannot be opened (for example, the simulator is not signed in to iCloud) the app falls
   back to a local store and shows a banner.

## Tests

```sh
swift test --package-path Packages/TradeLogKit     # core logic and integrations (runs on Linux too)
xcodebuild test -scheme TradeLog -destination 'platform=iOS Simulator,name=iPhone 16'   # app smoke test
```

## Project layout

```
project.yml                  XcodeGen spec
App/
  TradeLogApp.swift          @main, ModelContainer (CloudKit with local fallback), environment objects
  Models/                    SwiftData models (CloudKit-safe)
  Services/                  Keychain, sync, CSV import, prices, FX rates, backup, PDF, StoreKit, settings
  Features/                  SwiftUI screens (Dashboard, Trades, Positions, Calendar, Reports, Tax, ...)
  Resources/                 Assets, StoreKit config, privacy manifest
AppTests/                    Unit tests (model to TradeInput mapping)
Packages/TradeLogKit/        TradeLogCore (pure logic) and TradeLogIntegrations (connectors, providers)
docs/PLAN.md                 Product plan
```

Navigation: `NavigationSplitView` with a sidebar on iPad; a 5-tab `TabView` (Dashboard, Trades, Positions,
Reports, More) on compact width (iPhone).

## Roadmap

1. macOS target: add `macOS` to `supportedDestinations`, Mac menus and keyboard commands (UIKit use is already avoided)
2. Turn on purchase gating (`AppSettings.unlockAllForDevelopment` defaults to true in v1), App Store assets, privacy review
3. Trade replay, AI coach, more connectors (Coinbase Advanced, OKX, Tiger/Moomoo OpenAPI)

## Not verified

**v1 was written without compiling.** There was no Xcode or Swift toolchain in the authoring environment, so neither
the app target nor its tests have been built or run. Expect a round of compile fixes (SwiftData macro quirks,
type-checker complexity, API label mismatches against the package) when you first open the project.
The Swift package has its own tests and is the source of truth for the P&L and tax math.

## Disclaimer

TradeLog calculates gains using FIFO and Bank Negara Malaysia middle rates. Whether these gains are taxable depends on
LHDN's assessment of your trading activity (badges of trade). Consult a tax adviser. TradeLog is not financial advice.
