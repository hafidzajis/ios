import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseManager {
    static let productID = "com.hafidzajis.tradelog.lifetime"

    private(set) var product: Product?
    private(set) var hasEntitlement = false
    private(set) var isWorking = false
    var errorMessage: String?

    private let settings: AppSettings
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// True when the lifetime purchase is verified, or while the development override is on (default in v1).
    var isUnlocked: Bool { hasEntitlement || settings.unlockAllForDevelopment }

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    await self?.handle(result)
                }
            }
        }
        await loadProduct()
        await refreshEntitlements()
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            errorMessage = "Could not load the product: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                entitled = true
            }
        }
        hasEntitlement = entitled
    }

    func purchase() async {
        guard let product else {
            await loadProduct()
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            if transaction.productID == Self.productID {
                hasEntitlement = transaction.revocationDate == nil
            }
            await transaction.finish()
        case .unverified:
            errorMessage = "The purchase could not be verified."
        }
    }
}
