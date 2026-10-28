import SwiftUI
import StoreKit

struct PurchaseView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AppSettings.self) private var settings

    private let perks: [(String, String)] = [
        ("infinity", "Pay once, use forever. No subscription."),
        ("chart.line.uptrend.xyaxis", "Full analytics, calendar and R-multiple reports."),
        ("doc.text.magnifyingglass", "Malaysia tax report with BNM rates, PDF and CSV."),
        ("link", "Read-only exchange and broker sync."),
        ("icloud", "iCloud sync and daily backups across your devices."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("TradeLog Lifetime").font(.largeTitle.bold())
                Text("One purchase unlocks everything on iPhone and iPad.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(perks, id: \.0) { perk in
                        Label(perk.1, systemImage: perk.0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if purchases.hasEntitlement {
                    Label("Purchased. Thank you!", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                } else {
                    if settings.unlockAllForDevelopment {
                        Text("All features are currently unlocked in this version.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        Text(buyTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(purchases.isWorking || purchases.product == nil)

                    Button("Restore purchase") { Task { await purchases.restore() } }
                        .disabled(purchases.isWorking)
                }
                if let error = purchases.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Unlock TradeLog")
        .task { if purchases.product == nil { await purchases.loadProduct() } }
    }

    private var buyTitle: String {
        if let product = purchases.product { return "Unlock for \(product.displayPrice)" }
        return "Loading price..."
    }
}
