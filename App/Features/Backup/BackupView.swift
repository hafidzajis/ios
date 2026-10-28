import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(BackupService.self) private var backups

    @State private var pendingRestore: URL?
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var message: String?
    @State private var errorMessage: String?

    private var iCloudSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var body: some View {
        List {
            syncSection
            Section {
                Button {
                    Task {
                        do { try await backups.backupNow(context: context, settings: settings) }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Label("Back up now", systemImage: "externaldrive.badge.icloud")
                        if backups.isBusy { Spacer(); ProgressView() }
                    }
                }
                .disabled(backups.isBusy)
                LabeledContent("Last backup", value: settings.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                Button {
                    do { exportURL = try backups.exportTemporary(context: context) }
                    catch { errorMessage = error.localizedDescription }
                } label: { Label("Prepare export file", systemImage: "square.and.arrow.up") }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export", systemImage: "square.and.arrow.up.on.square") }
                }
                Button { showImporter = true } label: { Label("Import backup file", systemImage: "square.and.arrow.down") }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is made automatically once a day when you open the app (the last \(BackupService.keepCount) are kept). \(backups.usesICloudContainer ? "Backups are stored in iCloud Drive and visible in the Files app under TradeLog." : "iCloud Drive is unavailable, so backups are stored in the app's Documents folder.") API keys are never included.")
            }
            Section("Saved backups") {
                if backups.files.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                }
                ForEach(backups.files) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(file.date.formatted(date: .abbreviated, time: .shortened))
                            Text("\(file.name)  |  \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button { pendingRestore = file.url } label: { Label("Restore", systemImage: "arrow.counterclockwise") }
                            ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { Task { await backups.delete(file) } } label: { Label("Delete", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
            if let errorMessage { Section { Label(errorMessage, systemImage: "xmark.octagon").foregroundStyle(.red).font(.footnote) } }
        }
        .navigationTitle("Backup & Sync")
        .task { await backups.refreshList() }
        .refreshable { await backups.refreshList() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { outcome in
            switch outcome {
            case .success(let url): pendingRestore = url
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace all data", role: .destructive) { restore(.replaceAll) }
            Button("Merge (add missing items)") { restore(.merge) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Replace deletes everything currently in TradeLog first. Merge keeps your data and adds items from the backup that are not already present.")
        }
    }

    private var syncSection: some View {
        Section {
            if settings.isLocalOnlyFallback {
                Label("iCloud sync is unavailable. The database could not be opened with CloudKit, so data is stored on this device only.",
                      systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            LabeledContent("iCloud account", value: iCloudSignedIn ? "Signed in" : "Not signed in")
            LabeledContent("Database sync", value: settings.isLocalOnlyFallback ? "Off (local only)" : "CloudKit (private)")
        } header: {
            Text("iCloud sync")
        } footer: {
            Text("Trades, tags and playbooks sync between your devices through your private iCloud database. API keys sync through iCloud Keychain.")
        }
    }

    private func restore(_ mode: BackupService.RestoreMode) {
        guard let url = pendingRestore else { return }
        pendingRestore = nil
        do {
            let s = try backups.restore(from: url, mode: mode, context: context)
            message = "Restored \(s.trades) trades, \(s.accounts) accounts, \(s.setups) playbooks, \(s.tags) tags."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
