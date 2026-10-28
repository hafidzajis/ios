import Foundation
import Observation
import SwiftData
import TradeLogCore

private let backupContainerID = "iCloud.com.hafidzajis.tradelog"

@MainActor
@Observable
final class BackupService {
    struct BackupFile: Identifiable, Hashable {
        let url: URL
        let date: Date
        let size: Int
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    enum RestoreMode { case replaceAll, merge }

    struct RestoreSummary {
        var accounts = 0, setups = 0, tags = 0, trades = 0
    }

    private(set) var files: [BackupFile] = []
    private(set) var isBusy = false
    private(set) var usesICloudContainer = false
    var statusMessage: String?

    static let keepCount = 14

    // MARK: Locations

    /// iCloud ubiquity container `Documents/Backups` if available, otherwise the app's Documents/Backups.
    func backupDirectory() async -> URL {
        let icloud: URL? = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: backupContainerID)
        }.value
        let base: URL
        if let icloud {
            base = icloud.appendingPathComponent("Documents", isDirectory: true)
            usesICloudContainer = true
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            usesICloudContainer = false
        }
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refreshList() async {
        let dir = await backupDirectory()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        files = urls
            .filter { $0.lastPathComponent.hasPrefix("TradeLog-") && $0.pathExtension == "json" }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return BackupFile(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: Create

    func makeBackup(context: ModelContext) throws -> TradeLogBackup {
        var backup = TradeLogBackup()
        backup.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let setups = try context.fetch(FetchDescriptor<Setup>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        let trades = try context.fetch(FetchDescriptor<Trade>())
        let connections = try context.fetch(FetchDescriptor<Connection>())
        let rates = try context.fetch(FetchDescriptor<FXRate>())

        backup.accounts = accounts.map {
            .init(uuid: $0.uuid, name: $0.name, broker: $0.broker, connectorID: $0.connectorID, baseCurrency: $0.baseCurrency,
                  startingCapital: $0.startingCapital.plainString, notes: $0.notes, createdAt: $0.createdAt)
        }
        backup.setups = setups.map { .init(uuid: $0.uuid, name: $0.name, details: $0.details) }
        backup.tags = tags.map { .init(uuid: $0.uuid, name: $0.name, kind: $0.kindRaw, colorHex: $0.colorHex) }
        backup.trades = trades.map { t in
            .init(
                uuid: t.uuid, symbol: t.symbol, assetClass: t.assetClassRaw, side: t.sideRaw,
                leverage: t.leverage.plainString,
                plannedEntry: t.plannedEntry?.plainString, stopLoss: t.stopLoss?.plainString,
                takeProfit: t.takeProfit?.plainString, fundingFees: t.fundingFees.plainString,
                setupUUID: t.setup?.uuid, tagUUIDs: (t.tags ?? []).map(\.uuid),
                emotion: t.emotion, followedPlan: t.followedPlan, notes: t.notes, timeframe: t.timeframe,
                createdAt: t.createdAt, updatedAt: t.updatedAt, isArchived: t.isArchived,
                accountUUID: t.account?.uuid,
                fills: t.sortedFills.map {
                    .init(uuid: $0.uuid, action: $0.actionRaw, date: $0.date, price: $0.price.plainString,
                          quantity: $0.quantity.plainString, fee: $0.fee.plainString, externalID: $0.externalID)
                },
                attachments: t.sortedAttachments.map {
                    .init(uuid: $0.uuid, imageData: $0.imageData, caption: $0.caption, createdAt: $0.createdAt)
                }
            )
        }
        backup.connections = connections.map {
            .init(uuid: $0.uuid, connectorID: $0.connectorID, displayName: $0.displayName, lastSyncAt: $0.lastSyncAt,
                  isEnabled: $0.isEnabled, accountUUID: $0.account?.uuid)
        }
        backup.fxRates = rates.map {
            .init(dayKey: $0.dayKey, usdToMYR: $0.usdToMYR.plainString, fetchedAt: $0.fetchedAt, isManual: $0.isManual)
        }
        return backup
    }

    private func encode(_ backup: TradeLogBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    private static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "TradeLog-\(f.string(from: date)).json"
    }

    @discardableResult
    func backupNow(context: ModelContext, settings: AppSettings) async throws -> URL {
        isBusy = true
        defer { isBusy = false }
        let data = try encode(try makeBackup(context: context))
        let dir = await backupDirectory()
        let url = dir.appendingPathComponent(Self.fileName(for: Date()))
        try data.write(to: url, options: .atomic)
        settings.lastBackupAt = Date()
        prune(in: dir)
        await refreshList()
        statusMessage = "Backup saved: \(url.lastPathComponent)"
        return url
    }

    /// Writes a backup into the temporary directory for sharing/exporting.
    func exportTemporary(context: ModelContext) throws -> URL {
        let data = try encode(try makeBackup(context: context))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName(for: Date()))
        try data.write(to: url, options: .atomic)
        return url
    }

    func autoBackupIfNeeded(context: ModelContext, settings: AppSettings) async {
        if let last = settings.lastBackupAt, Date().timeIntervalSince(last) < 86_400 { return }
        // Nothing to back up on a fresh install.
        let hasData = ((try? context.fetchCount(FetchDescriptor<Trade>())) ?? 0) > 0
        guard hasData else { return }
        _ = try? await backupNow(context: context, settings: settings)
    }

    private func prune(in dir: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let backups = urls
            .filter { $0.lastPathComponent.hasPrefix("TradeLog-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(Self.keepCount) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    func delete(_ file: BackupFile) async {
        try? FileManager.default.removeItem(at: file.url)
        await refreshList()
    }

    // MARK: Restore

    func readBackup(from url: URL) throws -> TradeLogBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(TradeLogBackup.self, from: data)
        guard backup.schemaVersion <= 1 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "This backup was made by a newer version of TradeLog."])
        }
        return backup
    }

    @discardableResult
    func restore(from url: URL, mode: RestoreMode, context: ModelContext) throws -> RestoreSummary {
        let backup = try readBackup(from: url)
        var summary = RestoreSummary()

        if mode == .replaceAll {
            for t in try context.fetch(FetchDescriptor<Trade>()) { context.delete(t) }
            for a in try context.fetch(FetchDescriptor<Account>()) { context.delete(a) }
            for s in try context.fetch(FetchDescriptor<Setup>()) { context.delete(s) }
            for t in try context.fetch(FetchDescriptor<Tag>()) { context.delete(t) }
            for c in try context.fetch(FetchDescriptor<Connection>()) { context.delete(c) }
            for r in try context.fetch(FetchDescriptor<FXRate>()) { context.delete(r) }
            try context.save()
        }

        var accounts = Self.index(try context.fetch(FetchDescriptor<Account>()), by: \.uuid)
        var setups = Self.index(try context.fetch(FetchDescriptor<Setup>()), by: \.uuid)
        var tags = Self.index(try context.fetch(FetchDescriptor<Tag>()), by: \.uuid)
        let existingTrades = Set(try context.fetch(FetchDescriptor<Trade>()).map(\.uuid))
        let existingConnections = Set(try context.fetch(FetchDescriptor<Connection>()).map(\.uuid))
        var rates = Set(try context.fetch(FetchDescriptor<FXRate>()).map(\.dayKey))

        for dto in backup.accounts where accounts[dto.uuid] == nil {
            let a = Account(name: dto.name, broker: dto.broker, connectorID: dto.connectorID, startingCapital: Decimal(plain: dto.startingCapital))
            a.uuid = dto.uuid
            a.baseCurrency = dto.baseCurrency
            a.notes = dto.notes
            a.createdAt = dto.createdAt
            context.insert(a)
            accounts[dto.uuid] = a
            summary.accounts += 1
        }
        for dto in backup.setups where setups[dto.uuid] == nil {
            let s = Setup(name: dto.name, details: dto.details)
            s.uuid = dto.uuid
            context.insert(s)
            setups[dto.uuid] = s
            summary.setups += 1
        }
        for dto in backup.tags where tags[dto.uuid] == nil {
            let t = Tag(name: dto.name, kind: TagKind(rawValue: dto.kind) ?? .custom, colorHex: dto.colorHex)
            t.uuid = dto.uuid
            context.insert(t)
            tags[dto.uuid] = t
            summary.tags += 1
        }
        for dto in backup.trades where !existingTrades.contains(dto.uuid) {
            let trade = Trade(
                symbol: dto.symbol,
                assetClass: AssetClass(rawValue: dto.assetClass) ?? .usStock,
                side: TradeSide(rawValue: dto.side) ?? .long
            )
            trade.uuid = dto.uuid
            context.insert(trade)
            trade.leverage = Decimal(plain: dto.leverage)
            trade.plannedEntry = dto.plannedEntry.map { Decimal(plain: $0) }
            trade.stopLoss = dto.stopLoss.map { Decimal(plain: $0) }
            trade.takeProfit = dto.takeProfit.map { Decimal(plain: $0) }
            trade.fundingFees = Decimal(plain: dto.fundingFees)
            trade.emotion = dto.emotion
            trade.followedPlan = dto.followedPlan
            trade.notes = dto.notes
            trade.timeframe = dto.timeframe
            trade.createdAt = dto.createdAt
            trade.updatedAt = dto.updatedAt
            trade.isArchived = dto.isArchived
            trade.account = dto.accountUUID.flatMap { accounts[$0] }
            trade.setup = dto.setupUUID.flatMap { setups[$0] }
            let tagModels = dto.tagUUIDs.compactMap { tags[$0] }
            if !tagModels.isEmpty { trade.tags = tagModels }
            for f in dto.fills {
                let fill = Fill(
                    uuid: f.uuid, action: FillAction(rawValue: f.action) ?? .open, date: f.date,
                    price: Decimal(plain: f.price), quantity: Decimal(plain: f.quantity), fee: Decimal(plain: f.fee),
                    externalID: f.externalID
                )
                context.insert(fill)
                trade.addFill(fill)
            }
            for a in dto.attachments {
                let att = Attachment(uuid: a.uuid, imageData: a.imageData, caption: a.caption, createdAt: a.createdAt)
                context.insert(att)
                trade.addAttachment(att)
            }
            trade.refreshCache()
            summary.trades += 1
        }
        for dto in backup.connections where !existingConnections.contains(dto.uuid) {
            let c = Connection(connectorID: dto.connectorID, displayName: dto.displayName, account: dto.accountUUID.flatMap { accounts[$0] })
            c.uuid = dto.uuid
            c.lastSyncAt = dto.lastSyncAt
            c.isEnabled = dto.isEnabled
            context.insert(c)
        }
        for dto in backup.fxRates where !rates.contains(dto.dayKey) {
            context.insert(FXRate(dayKey: dto.dayKey, usdToMYR: Decimal(plain: dto.usdToMYR), fetchedAt: dto.fetchedAt, isManual: dto.isManual))
            rates.insert(dto.dayKey)
        }
        try context.save()
        return summary
    }

    private static func index<T>(_ items: [T], by key: KeyPath<T, UUID>) -> [UUID: T] {
        var dict: [UUID: T] = [:]
        for item in items where dict[item[keyPath: key]] == nil {
            dict[item[keyPath: key]] = item
        }
        return dict
    }
}
