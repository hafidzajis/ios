import SwiftUI
import SwiftData

@main
struct TradeLogApp: App {
    static let cloudContainerID = "iCloud.com.hafidzajis.tradelog"

    static let schema = Schema([
        Account.self, Trade.self, Fill.self, Tag.self, Setup.self,
        Attachment.self, Connection.self, FXRate.self,
    ])

    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var purchases: PurchaseManager
    @State private var prices = PriceService()
    @State private var sync = SyncCoordinator()
    @State private var fx = FXRateService()
    @State private var backups = BackupService()

    init() {
        let settings = AppSettings()
        let (container, localOnly) = Self.makeContainer()
        settings.isLocalOnlyFallback = localOnly
        self.container = container
        _settings = State(initialValue: settings)
        _purchases = State(initialValue: PurchaseManager(settings: settings))
    }

    /// CloudKit-backed store first; falls back to a local store (e.g. no iCloud account on the simulator).
    private static func makeContainer() -> (ModelContainer, Bool) {
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            return (try ModelContainer(for: schema, configurations: config), false)
        } catch {
            print("CloudKit store unavailable, using local store: \(error)")
        }
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return (try ModelContainer(for: schema, configurations: config), true)
        } catch {
            print("Local store unavailable, using in-memory store: \(error)")
        }
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return (try ModelContainer(for: schema, configurations: config), true)
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(purchases)
                .environment(prices)
                .environment(sync)
                .environment(fx)
                .environment(backups)
        }
        .modelContainer(container)
    }
}
