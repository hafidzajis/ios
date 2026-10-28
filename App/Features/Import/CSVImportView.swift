import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TradeLogCore
import TradeLogIntegrations

struct CSVImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var showImporter = false
    @State private var fileName: String?
    @State private var text: String?
    @State private var headers: [String] = []
    @State private var preview: [[String]] = []
    @State private var mapping: CSVColumnMapping?
    @State private var account: Account?
    @State private var assetClass: AssetClass = .usStock
    @State private var result: ImportResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Button { showImporter = true } label: {
                    Label(fileName ?? "Choose CSV file", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("Works with exports from most brokers (Moomoo, Webull, Coinbase and others). Map the columns below.")
            }

            if text != nil, mapping != nil {
                previewSection
                mappingSection
                Section("Destination") {
                    Picker("Account", selection: $account) {
                        Text("None").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                    }
                    Picker("Asset class", selection: $assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .onChange(of: assetClass) { _, new in mapping?.defaultAssetClass = new }
                }
                Section {
                    Button("Import", action: runImport).bold()
                }
            }

            if let result {
                Section("Result") {
                    LabeledContent("Executions read", value: "\(result.executionsReceived)")
                    LabeledContent("Duplicates skipped", value: "\(result.duplicatesSkipped)")
                    LabeledContent("Trades created", value: "\(result.tradesCreated)")
                    LabeledContent("Trades updated", value: "\(result.tradesUpdated)")
                }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "xmark.octagon").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Import CSV")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { outcome in
            handle(outcome)
        }
    }

    // MARK: Sections

    private var previewSection: some View {
        Section("Preview") {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { index, row in
                        Text(row.joined(separator: "  |  "))
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(index == 0 ? .bold : .regular)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var mappingSection: some View {
        Section("Column mapping") {
            requiredPicker("Date / time", \.date)
            requiredPicker("Symbol", \.symbol)
            requiredPicker("Side (buy/sell)", \.side)
            requiredPicker("Quantity", \.quantity)
            requiredPicker("Price", \.price)
            optionalPicker("Fee", \.fee)
            optionalPicker("Fee currency", \.feeCurrency)
            optionalPicker("Trade ID", \.externalID)
            LabeledContent("Date format") {
                TextField("auto, or e.g. yyyy-MM-dd HH:mm:ss", text: textBinding(\.dateFormat))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("Time zone") {
                TextField("e.g. America/New_York", text: textBinding(\.timeZoneID))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
        }
    }

    private func requiredPicker(_ title: String, _ keyPath: WritableKeyPath<CSVColumnMapping, String>) -> some View {
        Picker(title, selection: Binding(
            get: { mapping?[keyPath: keyPath] ?? "" },
            set: { mapping?[keyPath: keyPath] = $0 }
        )) {
            ForEach(headers, id: \.self) { Text($0).tag($0) }
        }
    }

    private func optionalPicker(_ title: String, _ keyPath: WritableKeyPath<CSVColumnMapping, String?>) -> some View {
        Picker(title, selection: Binding<String?>(
            get: { mapping?[keyPath: keyPath] ?? nil },
            set: { mapping?[keyPath: keyPath] = $0 }
        )) {
            Text("None").tag(String?.none)
            ForEach(headers, id: \.self) { Text($0).tag(Optional($0)) }
        }
    }

    private func textBinding(_ keyPath: WritableKeyPath<CSVColumnMapping, String?>) -> Binding<String> {
        Binding(
            get: { (mapping?[keyPath: keyPath] ?? nil) ?? "" },
            set: { mapping?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: Actions

    private func handle(_ outcome: Result<URL, Error>) {
        result = nil
        errorMessage = nil
        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            do {
                let content = try CSVImportService.readText(from: url)
                let hdrs = CSVImportService.headers(in: content)
                guard !hdrs.isEmpty else {
                    errorMessage = "The file has no header row."
                    return
                }
                fileName = url.lastPathComponent
                text = content
                headers = hdrs
                preview = CSVImportService.previewRows(in: content)
                mapping = CSVImportService.guessMapping(headers: hdrs, defaultAssetClass: assetClass)
                if let m = mapping { assetClass = m.defaultAssetClass }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runImport() {
        guard let text, let mapping else { return }
        errorMessage = nil
        do {
            result = try CSVImportService.importCSV(text: text, mapping: mapping, account: account, context: context)
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}
