import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(FXRateService.self) private var fx

    @State private var finnhubKey = ""
    @State private var showDisclaimer = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Display currency", selection: $settings.displayCurrency) {
                    Text("USD").tag("USD")
                    Text("MYR (converted)").tag("MYR")
                }
                if settings.displayCurrency == "MYR" {
                    LabeledContent("USD to MYR", value: Fmt.number(settings.displayRateMYR, digits: 4))
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Trades are recorded in USD. MYR converts P&L displays at the latest cached BNM rate. The tax report always uses the rate of each transaction day.")
            }
            .onChange(of: settings.displayCurrency) { _, new in
                if new == "MYR" { Task { await fx.refreshDisplayRate(settings: settings, context: context) } }
            }

            Section {
                LabeledContent("Risk per trade") {
                    HStack {
                        TextField("1", value: $settings.riskPerTradePercent, format: .number)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(maxWidth: 80)
                        Text("%")
                    }
                }
            } header: {
                Text("Risk")
            } footer: {
                Text("Your target risk per trade as a percentage of account capital.")
            }

            Section {
                SecureField(settings.hasFinnhubKey ? "Key saved (enter to replace)" : "Finnhub API key", text: $finnhubKey)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save key") {
                        settings.setFinnhubKey(finnhubKey)
                        finnhubKey = ""
                    }
                    .disabled(finnhubKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    if settings.hasFinnhubKey {
                        Button("Remove", role: .destructive) { settings.setFinnhubKey("") }
                    }
                }
            } header: {
                Text("Live prices")
            } footer: {
                Text("A free Finnhub key enables US stock quotes. Crypto prices come from Binance and CoinGecko without a key. The key is stored in your Keychain.")
            }

            Section {
                Toggle("Unlock all features (development)", isOn: $settings.unlockAllForDevelopment)
            } header: {
                Text("Developer")
            } footer: {
                Text("v1 ships with every feature unlocked. Turn this off to test purchase gating.")
            }

            Section("About") {
                LabeledContent("Version", value: version)
                Button("Tax and data disclaimer") { showDisclaimer = true }
            }
        }
        .navigationTitle("Settings")
        .alert("Disclaimer", isPresented: $showDisclaimer) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(TaxDisclaimer.text)\n\nTradeLog is a journaling tool and does not provide financial, investment or tax advice. Figures depend on the data you enter or import.")
        }
    }
}
