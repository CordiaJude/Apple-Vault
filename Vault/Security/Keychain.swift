import Foundation
import Security

/// A tiny wrapper around the Keychain for Vault's own secrets.
nonisolated enum Keychain {
    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    private static let service = "app.vault.keys"

    /// Reads a secret. `synchronizable` narrows the lookup to iCloud Keychain
    /// items (`true`) or device-only items (`false`); `nil` matches either.
    static func read(_ account: String, synchronizable: Bool? = nil) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizable.map { $0 as Any } ?? kSecAttrSynchronizableAny,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Error.unexpectedStatus(status)
        }
    }

    /// Stores `data`, only readable while the device is unlocked. By default it
    /// never leaves this device: it is excluded from backups and iCloud Keychain.
    static func write(_ data: Data, account: String, synchronizable: Bool = false) throws {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: synchronizable
                ? kSecAttrAccessibleWhenUnlocked
                : kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
