import Foundation
import SwiftData

/// A configured broker/exchange connection. Secrets live in the Keychain, never here.
@Model
final class Connection {
    var uuid: UUID = UUID()
    var connectorID: String = ""
    var displayName: String = ""
    var lastSyncAt: Date?
    var lastError: String?
    var isEnabled: Bool = true
    var account: Account?

    init(connectorID: String, displayName: String, account: Account? = nil) {
        self.uuid = UUID()
        self.connectorID = connectorID
        self.displayName = displayName
        self.account = account
    }
}
