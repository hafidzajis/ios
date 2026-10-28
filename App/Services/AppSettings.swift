import Foundation
import Observation
import TradeLogCore

@Observable
final class AppSettings {
    private enum Key {
        static let displayCurrency = "displayCurrency"
        static let displayRateMYR = "displayRateMYR"
        static let defaultAccountUUID = "defaultAccountUUID"
        static let riskPerTradePercent = "riskPerTradePercent"
        static let hasFinnhubKey = "hasFinnhubKey"
        static let lastBackupAt = "lastBackupAt"
        static let unlockAllForDevelopment = "unlockAllForDevelopment"
        static let seededTags = "seededTags"
    }

    private let defaults: UserDefaults

    /// "USD" or "MYR". MYR converts displayed P&L with `displayRateMYR` (latest cached BNM rate).
    var displayCurrency: String { didSet { defaults.set(displayCurrency, forKey: Key.displayCurrency) } }
    var displayRateMYR: Double { didSet { defaults.set(displayRateMYR, forKey: Key.displayRateMYR) } }
    var defaultAccountUUID: String? { didSet { defaults.set(defaultAccountUUID, forKey: Key.defaultAccountUUID) } }
    var riskPerTradePercent: Double { didSet { defaults.set(riskPerTradePercent, forKey: Key.riskPerTradePercent) } }
    var hasFinnhubKey: Bool { didSet { defaults.set(hasFinnhubKey, forKey: Key.hasFinnhubKey) } }
    var lastBackupAt: Date? { didSet { defaults.set(lastBackupAt, forKey: Key.lastBackupAt) } }
    var unlockAllForDevelopment: Bool { didSet { defaults.set(unlockAllForDevelopment, forKey: Key.unlockAllForDevelopment) } }
    var tagsSeeded: Bool { didSet { defaults.set(tagsSeeded, forKey: Key.seededTags) } }

    /// Runtime flag (not persisted): the CloudKit-backed store could not be opened, data is local only.
    var isLocalOnlyFallback = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayCurrency = defaults.string(forKey: Key.displayCurrency) ?? "USD"
        let rate = defaults.double(forKey: Key.displayRateMYR)
        displayRateMYR = rate > 0 ? rate : 4.5
        defaultAccountUUID = defaults.string(forKey: Key.defaultAccountUUID)
        let risk = defaults.double(forKey: Key.riskPerTradePercent)
        riskPerTradePercent = risk > 0 ? risk : 1
        hasFinnhubKey = defaults.bool(forKey: Key.hasFinnhubKey)
        lastBackupAt = defaults.object(forKey: Key.lastBackupAt) as? Date
        unlockAllForDevelopment = defaults.object(forKey: Key.unlockAllForDevelopment) as? Bool ?? true
        tagsSeeded = defaults.bool(forKey: Key.seededTags)
    }

    // MARK: Money display

    func convert(_ usd: Decimal) -> Decimal {
        displayCurrency == "MYR" ? usd * Decimal(displayRateMYR) : usd
    }

    func money(_ usd: Decimal, fractionDigits: Int = 2) -> String {
        MoneyFormat.string(convert(usd), currencyCode: displayCurrency, fractionDigits: fractionDigits)
    }

    func signedMoney(_ usd: Decimal) -> String {
        MoneyFormat.signed(convert(usd), currencyCode: displayCurrency)
    }

    // MARK: Finnhub key (Keychain)

    var finnhubKey: String? { KeychainStore.get(account: KeychainStore.finnhubAccount) }

    func setFinnhubKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: KeychainStore.finnhubAccount)
            hasFinnhubKey = false
        } else {
            do {
                try KeychainStore.set(trimmed, account: KeychainStore.finnhubAccount)
                hasFinnhubKey = true
            } catch {
                hasFinnhubKey = false
            }
        }
    }
}
