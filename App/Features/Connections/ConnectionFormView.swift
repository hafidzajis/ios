import SwiftUI
import SwiftData
import TradeLogCore

struct ConnectionFormView: View {
    let connection: Connection?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(sort: \Account.name) private var accounts: [Account]

    @State private var connectorID: String
    @State private var displayName: String
    @State private var account: Account?
    @State private var values: [String: String]
    @State private var testMessage: String?
    @State private var testOK = false
    @State private var isTesting = false

    private let connectors = ConnectorInfo.all

    init(connection: Connection?) {
        self.connection = connection
        let infos = ConnectorInfo.all
        let id = connection?.connectorID ?? infos.first?.id ?? ""
        _connectorID = State(initialValue: id)
        _displayName = State(initialValue: connection?.displayName ?? infos.first?.name ?? "")
        _account = State(initialValue: connection?.account)
        var initial: [String: String] = [:]
        if let connection {
            initial = KeychainStore.credentials(connectionID: connection.uuid, keys: SyncCoordinator.keys(forConnector: id))
        }
        _values = State(initialValue: initial)
    }

    private var fields: [CredentialField] {
        connectors.first { $0.id == connectorID }?.fields ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Picker("Provider", selection: $connectorID) {
                        ForEach(connectors) { Text($0.name).tag($0.id) }
                    }
                    .disabled(connection != nil)
                    .onChange(of: connectorID) { _, new in
                        if connection == nil {
                            displayName = connectors.first { $0.id == new }?.name ?? displayName
                            values = [:]
                        }
                    }
                    TextField("Name", text: $displayName)
                    Picker("Account", selection: $account) {
                        Text("Create automatically").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Section {
                    ForEach(fields) { field in
                        if field.isSecret {
                            SecureField(field.label, text: binding(for: field.key))
                                .autocorrectionDisabled()
                        } else {
                            TextField(field.label, text: binding(for: field.key))
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Always create READ-ONLY API keys. Never enable trading or withdrawals.")
                }
                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isTesting || fields.isEmpty)
                    if let testMessage {
                        Label(testMessage, systemImage: testOK ? "checkmark.circle" : "xmark.octagon")
                            .foregroundStyle(testOK ? Color.green : Color.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(connection == nil ? "New Connection" : "Edit Connection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || connectorID.isEmpty)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        if let error = await sync.test(connectorID: connectorID, credentials: values) {
            testOK = false
            testMessage = error
        } else {
            testOK = true
            testMessage = "Connection works."
        }
    }

    private func save() {
        let target: Connection
        if let connection {
            target = connection
        } else {
            target = Connection(connectorID: connectorID, displayName: displayName)
            context.insert(target)
        }
        target.displayName = displayName.trimmingCharacters(in: .whitespaces)
        target.account = account
        for field in fields {
            let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                KeychainStore.delete(account: KeychainStore.account(connectionID: target.uuid, key: field.key))
            } else {
                try? KeychainStore.setCredential(value, connectionID: target.uuid, key: field.key)
            }
        }
        try? context.save()
        dismiss()
    }
}
