import SwiftUI
import SwiftData
import TradeLogCore

struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query private var trades: [Trade]

    @State private var editing: Tag?
    @State private var showNew = false

    private var stats: [String: BreakdownRow] {
        let report = PerformanceAnalyzer.analyze(trades.filter { !$0.isArchived }.snapshots)
        return Dictionary((report.breakdowns[.tag] ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let stats = stats
        List {
            ForEach(TagKind.allCases) { kind in
                let items = tags.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.title) {
                        ForEach(items) { tag in
                            Button { editing = tag } label: {
                                HStack {
                                    Text(tag.name)
                                    Spacer()
                                    if let row = stats[tag.name] {
                                        Text("\(row.trades)  \(Fmt.percent(row.winRate, digits: 0))")
                                            .font(.caption).foregroundStyle(.secondary)
                                        PnLText(value: row.netPnL).font(.caption)
                                    } else {
                                        Text("unused").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(items[i]) }
                            try? context.save()
                        }
                    }
                }
            }
        }
        .overlay {
            if tags.isEmpty {
                EmptyStateView(title: "No tags", systemImage: "tag", message: "Tags describe indicators, themes and mistakes.")
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New Tag", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { TagEditorSheet(tag: nil, existing: tags) }
        .sheet(item: $editing) { TagEditorSheet(tag: $0, existing: tags) }
    }
}

private struct TagEditorSheet: View {
    let tag: Tag?
    let existing: [Tag]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kind: TagKind = .custom

    private var isDuplicate: Bool {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return existing.contains { $0.name.lowercased() == n && $0.kind == kind && $0 !== tag }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(TagKind.allCases) { Text($0.title).tag($0) }
                }
                if isDuplicate {
                    Text("A tag with this name already exists.").foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate)
                }
            }
            .onAppear {
                if let tag { name = tag.name; kind = tag.kind }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let tag {
            tag.name = trimmed
            tag.kind = kind
        } else {
            context.insert(Tag(name: trimmed, kind: kind, colorHex: kind == .mistake ? "#FF453A" : "#0A84FF"))
        }
        try? context.save()
        dismiss()
    }
}
