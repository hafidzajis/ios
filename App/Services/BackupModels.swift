import Foundation

/// Versioned, Codable snapshot of all user data. Decimals are encoded as strings to avoid precision loss.
/// API secrets are never included.
struct TradeLogBackup: Codable {
    var schemaVersion: Int = 1
    var createdAt: Date = Date()
    var appVersion: String = ""
    var accounts: [AccountDTO] = []
    var setups: [SetupDTO] = []
    var tags: [TagDTO] = []
    var trades: [TradeDTO] = []
    var connections: [ConnectionDTO] = []
    var fxRates: [FXRateDTO] = []

    struct AccountDTO: Codable {
        var uuid: UUID
        var name: String
        var broker: String
        var connectorID: String?
        var baseCurrency: String
        var startingCapital: String
        var notes: String
        var createdAt: Date
    }

    struct SetupDTO: Codable {
        var uuid: UUID
        var name: String
        var details: String
    }

    struct TagDTO: Codable {
        var uuid: UUID
        var name: String
        var kind: String
        var colorHex: String
    }

    struct FillDTO: Codable {
        var uuid: UUID
        var action: String
        var date: Date
        var price: String
        var quantity: String
        var fee: String
        var externalID: String?
    }

    struct AttachmentDTO: Codable {
        var uuid: UUID
        var imageData: Data? // base64 in JSON
        var caption: String
        var createdAt: Date
    }

    struct TradeDTO: Codable {
        var uuid: UUID
        var symbol: String
        var assetClass: String
        var side: String
        var leverage: String
        var plannedEntry: String?
        var stopLoss: String?
        var takeProfit: String?
        var fundingFees: String
        var setupUUID: UUID?
        var tagUUIDs: [UUID]
        var emotion: String?
        var followedPlan: Bool?
        var notes: String
        var timeframe: String?
        var createdAt: Date
        var updatedAt: Date
        var isArchived: Bool
        var accountUUID: UUID?
        var fills: [FillDTO]
        var attachments: [AttachmentDTO]
    }

    struct ConnectionDTO: Codable {
        var uuid: UUID
        var connectorID: String
        var displayName: String
        var lastSyncAt: Date?
        var isEnabled: Bool
        var accountUUID: UUID?
    }

    struct FXRateDTO: Codable {
        var dayKey: String
        var usdToMYR: String
        var fetchedAt: Date
        var isManual: Bool
    }
}

extension Decimal {
    /// Locale-independent string for persistence.
    var plainString: String { "\(self)" }

    init(plain: String?) {
        self = plain.flatMap { Decimal(string: $0) } ?? 0
    }
}
