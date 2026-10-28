import Foundation
import Security

/// Generic-password Keychain wrapper. Items are synchronizable (iCloud Keychain) and available after first unlock.
enum KeychainStore {
    static let service = "com.hafidzajis.tradelog.connections"
    static let finnhubAccount = "settings.finnhub"

    enum KeychainError: Error, LocalizedError {
        case unhandled(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unhandled(let status): return "Keychain error \(status)"
            }
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // MARK: Connection credentials

    static func account(connectionID: UUID, key: String) -> String {
        "\(connectionID.uuidString).\(key)"
    }

    static func setCredential(_ value: String, connectionID: UUID, key: String) throws {
        try set(value, account: account(connectionID: connectionID, key: key))
    }

    static func credentials(connectionID: UUID, keys: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for key in keys {
            if let v = get(account: account(connectionID: connectionID, key: key)) { result[key] = v }
        }
        return result
    }

    static func deleteCredentials(connectionID: UUID, keys: [String]) {
        for key in keys { delete(account: account(connectionID: connectionID, key: key)) }
    }
}
