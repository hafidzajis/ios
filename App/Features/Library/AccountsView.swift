import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var editing: Account?
    @State private var showNew = false

    var body: some View {
        List {
            ForEach(accounts) { account in
                Button { editing = account } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.headline)
                            Text(account.broker.isEmpty ? "Manual account" : account.broker)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(settings.money(account.startingCapital, fractionDigits: 0)).monospacedDigit()
                            if settings.defaultAccountUUID == account.uuid.uuidString {
                                Text("Default").font(.caption2).foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(accounts[i]) }
                try? context.save()
            }
        }
        .overlay {
            if accounts.isEmpty {
                EmptyStateView(title: "No accounts", systemImage: "building.columns",
                               message: "Accounts group trades by broker or wallet. Starting capital drives risk percentages.")
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("New Account", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { AccountEditorSheet(account: nil) }
        .sheet(item: $editing) { AccountEditorSheet(account: $0) }
    }
}

private struct AccountEditorSheet: View {
    let account: Account?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var name = ""
    @State private var broker = ""
    @State private var capital: Decimal? = nil
    @State private var notes = ""
    @State private var makeDefault = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Broker / exchange", text: $broker)
                LabeledContent("Starting capital (USD)") { DecimalField("0", value: $capital) }
                Toggle("Default account for new trades", isOn: $makeDefault)
                Section("Notes") { TextEditor(text: $notes).frame(minHeight: 80) }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
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
                if let account {
                    name = account.name
                    broker = account.broker
                    capital = account.startingCapital
                    notes = account.notes
                    makeDefault = settings.defaultAccountUUID == account.uuid.uuidString
                }
            }
        }
    }

    private func save() {
        let target: Account
        if let account {
            target = account
        } else {
            target = Account(name: name)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.broker = broker
        target.startingCapital = capital ?? 0
        target.notes = notes
        if makeDefault {
            settings.defaultAccountUUID = target.uuid.uuidString
        } else if settings.defaultAccountUUID == target.uuid.uuidString {
            settings.defaultAccountUUID = nil
        }
        try? context.save()
        dismiss()
    }
}
