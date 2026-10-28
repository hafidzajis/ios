import SwiftUI
import SwiftData
import PhotosUI
import TradeLogCore

struct TradeEditorView: View {
    let trade: Trade?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Setup.name) private var setups: [Setup]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var draft: TradeDraft
    @State private var pickerItems: [PhotosPickerItem] = []

    init(trade: Trade?, prefill: TradeDraft? = nil) {
        self.trade = trade
        _draft = State(initialValue: prefill ?? trade.map { TradeDraft(trade: $0) } ?? TradeDraft())
    }

    private var metrics: TradeMetrics { TradeCalculator.metrics(for: draft.input()) }
    private var errors: [String] { draft.validationErrors }

    var body: some View {
        NavigationStack {
            Form {
                tradeSection
                planSection
                FillsEditorSection(fills: $draft.fills)
                if draft.assetClass == .cryptoPerp {
                    Section("Funding") {
                        LabeledContent("Net funding paid (USD)") { DecimalField("0.00", value: $draft.fundingFees) }
                    }
                }
                contextSection
                tagsSection
                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 120)
                }
                screenshotsSection
                if !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle(trade == nil ? "New Trade" : "Edit Trade")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!errors.isEmpty)
                }
            }
            .onAppear(perform: applyDefaultAccount)
            .onChange(of: pickerItems) { _, items in loadPhotos(items) }
        }
    }

    // MARK: Sections

    private var tradeSection: some View {
        Section("Trade") {
            Picker("Account", selection: $draft.account) {
                Text("None").tag(Account?.none)
                ForEach(accounts) { Text($0.name).tag(Optional($0)) }
            }
            LabeledContent("Symbol") {
                TextField("AAPL, BTCUSDT", text: $draft.symbol)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled()
                    .onChange(of: draft.symbol) { _, new in
                        let upper = new.uppercased()
                        if upper != new { draft.symbol = upper }
                    }
            }
            Picker("Asset class", selection: $draft.assetClass) {
                ForEach(AssetClass.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Side", selection: $draft.side) {
                Text("Long").tag(TradeSide.long)
                Text("Short").tag(TradeSide.short)
            }
            .pickerStyle(.segmented)
            LabeledContent("Leverage") {
                HStack {
                    DecimalField("1", value: $draft.leverage)
                    Text("x").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            LabeledContent("Planned entry") { DecimalField("0.00", value: $draft.plannedEntry) }
            LabeledContent("Stop loss") { DecimalField("0.00", value: $draft.stopLoss) }
            LabeledContent("Take profit") { DecimalField("0.00", value: $draft.takeProfit) }
            LabeledContent("Planned risk") {
                if let risk = metrics.plannedRisk {
                    VStack(alignment: .trailing) {
                        Text(settings.money(risk)).monospacedDigit()
                        if let pct = riskPercent(risk) {
                            Text("\(Fmt.number(pct))% of account").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Reward : risk") {
                Text(metrics.plannedRewardRatio.map { "1 : \(Fmt.decimal($0))" } ?? "—")
                    .foregroundStyle(metrics.plannedRewardRatio == nil ? Color.secondary : Color.primary)
            }
        } header: {
            Text("Plan")
        } footer: {
            Text("Risk uses the stop distance times opened quantity. Account percent uses the account's starting capital.")
        }
    }

    private func riskPercent(_ risk: Decimal) -> Double? {
        guard let capital = draft.account?.startingCapital, capital > 0 else { return nil }
        return (risk / capital).doubleValue * 100
    }

    private var contextSection: some View {
        Section("Context") {
            Picker("Setup", selection: $draft.setup) {
                Text("None").tag(Setup?.none)
                ForEach(setups) { Text($0.name).tag(Optional($0)) }
            }
            LabeledContent("Timeframe") {
                TextField("e.g. 15m, 4h, 1D", text: $draft.timeframe).multilineTextAlignment(.trailing)
            }
            Picker("Emotion", selection: $draft.emotion) {
                Text("—").tag(Emotion?.none)
                ForEach(Emotion.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker("Followed plan", selection: $draft.followedPlan) {
                Text("—").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            if tags.isEmpty {
                Text("No tags yet. Create some under Tags.").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        let selected = draft.tagIDs.contains(tag.uuid)
                        Button {
                            if selected { draft.tagIDs.remove(tag.uuid) } else { draft.tagIDs.insert(tag.uuid) }
                        } label: {
                            Text(tag.name)
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var screenshotsSection: some View {
        Section("Screenshots") {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                Label("Add screenshots", systemImage: "photo.badge.plus")
            }
            ForEach($draft.attachments) { $att in
                HStack(spacing: 12) {
                    DataImage(data: att.data)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    TextField("Caption", text: $att.caption)
                    Button(role: .destructive) {
                        let id = att.id
                        draft.attachments.removeAll { $0.id == id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: Actions

    private func applyDefaultAccount() {
        guard trade == nil, draft.account == nil else { return }
        if let id = settings.defaultAccountUUID, let match = accounts.first(where: { $0.uuid.uuidString == id }) {
            draft.account = match
        } else if accounts.count == 1 {
            draft.account = accounts.first
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = ImageSupport.compressedJPEG(from: data) {
                    draft.attachments.append(AttachmentDraft(data: jpeg))
                }
            }
            pickerItems = []
        }
    }

    private func save() {
        guard errors.isEmpty else { return }
        let target: Trade
        if let trade {
            target = trade
        } else {
            target = Trade(symbol: draft.symbol, assetClass: draft.assetClass, side: draft.side)
            context.insert(target)
        }
        draft.apply(to: target, context: context, allTags: tags)
        try? context.save()
        dismiss()
    }
}
