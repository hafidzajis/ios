import SwiftUI
import SwiftData
import TradeLogCore

struct TradeDetailView: View {
    let trade: Trade

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(PriceService.self) private var prices

    @State private var showEditor = false
    @State private var duplicateDraft: TradeDraft?
    @State private var confirmDelete = false
    @State private var selectedImage: Attachment?

    var body: some View {
        let m = trade.metrics
        List {
            headerSection(m)
            metricsSection(m)
            fillsSection
            planSection(m)
            contextSection
            if !trade.notes.isEmpty {
                Section("Notes") { Text(trade.notes) }
            }
            gallerySection
        }
        .navigationTitle(trade.symbol)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { duplicateDraft = TradeDraft.duplicating(trade) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button {
                        trade.isArchived.toggle()
                        try? context.save()
                    } label: { Label(trade.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: { Label("Actions", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showEditor) { TradeEditorView(trade: trade) }
        .sheet(isPresented: Binding(get: { duplicateDraft != nil }, set: { if !$0 { duplicateDraft = nil } })) {
            TradeEditorView(trade: nil, prefill: duplicateDraft)
        }
        .sheet(item: $selectedImage) { ScreenshotViewer(attachment: $0) }
        .confirmationDialog("Delete this trade?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Trade", role: .destructive) {
                context.delete(trade)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Its fills and screenshots will be removed too.")
        }
    }

    // MARK: Sections

    private func headerSection(_ m: TradeMetrics) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(trade.symbol).font(.title2.bold())
                    SideBadge(side: trade.side)
                    OutcomeBadge(outcome: m.outcome)
                    if trade.leverage > 1 { Text("\(Fmt.plain(trade.leverage))x").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Realized P&L").font(.caption).foregroundStyle(.secondary)
                        PnLText(value: m.netRealizedPnL).font(.title.weight(.semibold))
                    }
                    VStack(alignment: .leading) {
                        Text("R multiple").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.r(m.rMultiple)).font(.title3).foregroundStyle(m.rMultiple.map { Color.pnl($0) } ?? .secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("Return on margin").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.percent(m.returnOnMargin?.doubleValue)).font(.title3)
                            .foregroundStyle(m.returnOnMargin.map { Color.pnl($0) } ?? .secondary)
                    }
                }
                if m.outcome == .open, let price = prices.price(for: trade) {
                    let unrealized = TradeCalculator.unrealizedPnL(for: trade.snapshot(), metrics: m, currentPrice: price)
                    HStack {
                        Text("Live: \(Fmt.plain(price))").foregroundStyle(.secondary)
                        Spacer()
                        Text("Unrealized").font(.caption).foregroundStyle(.secondary)
                        PnLText(value: unrealized).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func metricsSection(_ m: TradeMetrics) -> some View {
        Section("Metrics") {
            LabeledContent("Avg entry", value: Fmt.plain(m.avgEntryPrice))
            LabeledContent("Avg exit", value: Fmt.plain(m.avgExitPrice))
            LabeledContent("Opened qty", value: Fmt.plain(m.openedQuantity))
            LabeledContent("Closed qty", value: Fmt.plain(m.closedQuantity))
            LabeledContent("Remaining qty", value: Fmt.plain(m.remainingQuantity))
            LabeledContent("Position value", value: settings.money(m.positionValue))
            LabeledContent("Margin used", value: settings.money(m.marginUsed))
            LabeledContent("Gross P&L") { PnLText(value: m.grossRealizedPnL) }
            LabeledContent("Fees", value: settings.money(m.totalFees))
            if trade.assetClass == .cryptoPerp {
                LabeledContent("Funding paid", value: settings.money(trade.fundingFees))
            }
            LabeledContent("Opened", value: m.openDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            LabeledContent("Closed", value: m.closeDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            LabeledContent("Holding time", value: Fmt.duration(m.holdingSeconds))
        }
    }

    private var fillsSection: some View {
        Section("Fills") {
            ForEach(trade.sortedFills) { fill in
                HStack {
                    Text(fill.action == .open ? "OPEN" : "CLOSE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(fill.action == .open ? Color.blue : Color.orange)
                        .frame(width: 48, alignment: .leading)
                    VStack(alignment: .leading) {
                        Text("\(Fmt.plain(fill.quantity)) @ \(Fmt.plain(fill.price))").monospacedDigit()
                        Text(fill.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if fill.fee > 0 {
                        Text("fee \(Fmt.decimal(fill.fee))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func planSection(_ m: TradeMetrics) -> some View {
        Section("Plan vs actual") {
            LabeledContent("Entry", value: "\(Fmt.plain(trade.plannedEntry)) → \(Fmt.plain(m.avgEntryPrice))")
            LabeledContent("Stop loss", value: Fmt.plain(trade.stopLoss))
            LabeledContent("Take profit", value: Fmt.plain(trade.takeProfit))
            LabeledContent("Planned risk", value: m.plannedRisk.map { settings.money($0) } ?? "—")
            LabeledContent("Planned R:R", value: m.plannedRewardRatio.map { "1 : \(Fmt.decimal($0))" } ?? "—")
            LabeledContent("Realized R", value: Fmt.r(m.rMultiple))
        }
    }

    private var contextSection: some View {
        Section("Context") {
            LabeledContent("Account", value: trade.account?.name ?? "—")
            LabeledContent("Setup", value: trade.setup?.name ?? "—")
            LabeledContent("Timeframe", value: trade.timeframe ?? "—")
            LabeledContent("Emotion", value: trade.emotion ?? "—")
            LabeledContent("Followed plan", value: trade.followedPlan.map { $0 ? "Yes" : "No" } ?? "—")
            if let tags = trade.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags.sorted { $0.name < $1.name }) { tag in
                        Text(tag.name)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gallerySection: some View {
        let items = trade.sortedAttachments
        if !items.isEmpty {
            Section("Screenshots") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(items) { att in
                        Button { selectedImage = att } label: {
                            DataImage(data: att.imageData)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ScreenshotViewer: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                DataImage(data: attachment.imageData, contentMode: .fit)
                    .frame(minWidth: 300, minHeight: 300)
            }
            .navigationTitle(attachment.caption.isEmpty ? "Screenshot" : attachment.caption)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
