import SwiftUI
import SwiftData
import TradeLogCore

struct PlaybooksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Setup.name) private var setups: [Setup]
    @Query private var trades: [Trade]

    @State private var editing: Setup?
    @State private var showNew = false

    private var stats: [String: BreakdownRow] {
        let report = PerformanceAnalyzer.analyze(trades.filter { !$0.isArchived }.snapshots)
        return Dictionary((report.breakdowns[.setup] ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let stats = stats
        List {
            ForEach(setups) { setup in
                Button { editing = setup } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setup.name).font(.headline)
                        if !setup.details.isEmpty {
                            Text(setup.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let row = stats[setup.name] {
                            HStack(spacing: 12) {
                                Text("\(row.trades) trades")
                                Text("Win \(Fmt.percent(row.winRate, digits: 0))")
                                PnLText(value: row.netPnL)
                                Text("Avg \(Fmt.r(row.averageR))")
                            }
                            .font(.caption)
                        } else {
                            Text("No closed trades yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(setups[i]) }
                try? context.save()
            }
        }
        .overlay {
            if setups.isEmpty {
                EmptyStateView(title: "No playbooks", systemImage: "book.closed",
                               message: "Define your setups (e.g. Breakout, Pullback) and compare their results.")
            }
        }
        .navigationTitle("Playbooks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New Playbook", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { SetupEditorSheet(setup: nil) }
        .sheet(item: $editing) { SetupEditorSheet(setup: $0) }
    }
}

private struct SetupEditorSheet: View {
    let setup: Setup?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Rules and notes") {
                    TextEditor(text: $details).frame(minHeight: 160)
                }
            }
            .navigationTitle(setup == nil ? "New Playbook" : "Edit Playbook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let setup { name = setup.name; details = setup.details }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let setup {
            setup.name = trimmed
            setup.details = details
        } else {
            context.insert(Setup(name: trimmed, details: details))
        }
        try? context.save()
        dismiss()
    }
}
