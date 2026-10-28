import Foundation
import Observation
import SwiftData
import TradeLogCore
import TradeLogIntegrations

@MainActor
@Observable
final class SyncCoordinator {
    var syncingIDs: Set<UUID> = []

    func isSyncing(_ connection: Connection) -> Bool { syncingIDs.contains(connection.uuid) }

    static func keys(forConnector id: String) -> [String] {
        ConnectorRegistry.type(for: id)?.credentialFields.map(\.key) ?? []
    }

    static func makeConnector(id: String, credentials: [String: String]) throws -> any BrokerConnector {
        guard let type = ConnectorRegistry.type(for: id) else {
            throw IntegrationError.unsupported("Unknown connector \(id)")
        }
        return type.init(credentials: credentials, session: URLSessionHTTPClient())
    }

    /// Verifies credentials by fetching the last day of executions. Returns nil on success, otherwise a message.
    func test(connectorID: String, credentials: [String: String]) async -> String? {
        do {
            let connector = try Self.makeConnector(id: connectorID, credentials: credentials)
            _ = try await connector.fetchExecutions(since: Date().addingTimeInterval(-86_400))
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    @discardableResult
    func sync(_ connection: Connection, context: ModelContext) async -> ImportResult? {
        guard !syncingIDs.contains(connection.uuid) else { return nil }
        syncingIDs.insert(connection.uuid)
        defer { syncingIDs.remove(connection.uuid) }
        do {
            let keys = Self.keys(forConnector: connection.connectorID)
            let creds = KeychainStore.credentials(connectionID: connection.uuid, keys: keys)
            let connector = try Self.makeConnector(id: connection.connectorID, credentials: creds)
            let since = connection.lastSyncAt.map { $0.addingTimeInterval(-2 * 86_400) }
            let executions = try await connector.fetchExecutions(since: since)

            let account: Account
            if let existing = connection.account {
                account = existing
            } else {
                let created = Account(name: connection.displayName, broker: connection.connectorID, connectorID: connection.connectorID)
                context.insert(created)
                connection.account = created
                account = created
            }
            let result = try ImportMerger.merge(executions: executions, account: account, context: context)
            connection.lastSyncAt = Date()
            connection.lastError = nil
            try? context.save()
            return result
        } catch {
            connection.lastError = Self.describe(error)
            try? context.save()
            return nil
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? IntegrationError {
            switch e {
            case .missingCredential(let k): return "Missing credential: \(k)"
            case .http(let status, let body): return "HTTP \(status): \(body.prefix(160))"
            case .decoding(let m): return "Unexpected response: \(m)"
            case .unsupported(let m): return m
            }
        }
        return error.localizedDescription
    }
}
