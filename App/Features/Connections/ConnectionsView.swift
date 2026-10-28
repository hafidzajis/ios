import SwiftUI
import SwiftData
import TradeLogCore
import TradeLogIntegrations

struct ConnectorInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let fields: [CredentialField]

    static var all: [ConnectorInfo] {
        ConnectorRegistry.all.map {
            ConnectorInfo(id: $0.connectorID, name: $0.displayName, fields: $0.credentialFields)
        }
    }
}

struct ConnectionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Query(sort: \Connection.displayName) private var connections: [Connection]

    @State private var showNew = false
    @State private var editing: Connection?
    @State private var lastResult: String?

    var body: some View {
        List {
            Section {
                ForEach(connections) { connection in
                    row(connection)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Always create READ-ONLY API keys. TradeLog only reads your trade history and never needs trading or withdrawal permissions. Keys are stored in your Keychain, not in the database or backups.")
            }
            if let lastResult {
                Section { Text(lastResult).font(.footnote) }
            }
        }
        .overlay {
            if connections.isEmpty {
                EmptyStateView(title: "No connections", systemImage: "link",
                               message: "Connect an exchange or broker to import trades automatically.")
            }
        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Label("Add Connection", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showNew) { ConnectionFormView(connection: nil) }
        .sheet(item: $editing) { ConnectionFormView(connection: $0) }
    }

    private func row(_ c: Connection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(c.displayName).font(.headline)
                    Text(ConnectorInfo.all.first { $0.id == c.connectorID }?.name ?? c.connectorID)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if sync.isSyncing(c) {
                    ProgressView()
                } else {
                    Button("Sync now") { runSync(c) }.buttonStyle(.bordered)
                }
            }
            if let last = c.lastSyncAt {
                Text("Last sync \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Never synced").font(.caption).foregroundStyle(.secondary)
            }
            if let error = c.lastError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            Button("Edit credentials") { editing = c }.font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func runSync(_ c: Connection) {
        Task {
            if let r = await sync.sync(c, context: context) {
                lastResult = "\(c.displayName): \(r.executionsImported) new executions, \(r.tradesCreated) trades created, \(r.tradesUpdated) updated, \(r.duplicatesSkipped) duplicates skipped."
            } else {
                lastResult = nil
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let c = connections[index]
            KeychainStore.deleteCredentials(connectionID: c.uuid, keys: SyncCoordinator.keys(forConnector: c.connectorID))
            context.delete(c)
        }
        try? context.save()
    }
}
