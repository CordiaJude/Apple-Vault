import CommonCrypto
import CryptoKit
import Foundation
import Synchronization

/// Encrypts everything sensitive in Vault (images, PDFs, fields, notes and
/// recognized text) with AES-256-GCM.
///
/// The 256-bit key is generated on first launch and kept in the Keychain,
/// readable only while this iPhone is unlocked and never included in backups.
/// On top of that, every file Vault writes uses Data Protection "Complete", so
/// it is also encrypted by iOS with a key derived from your passcode.
nonisolated enum VaultCrypto {
    enum Error: Swift.Error, LocalizedError {
        case keyUnavailable
        case invalidBackup
        case wrongPassword

        var errorDescription: String? {
            switch self {
            case .keyUnavailable: String(localized: "Vault’s encryption key isn’t available. Unlock your iPhone and try again.")
            case .invalidBackup: String(localized: "This file isn’t a Vault backup, or it’s damaged.")
            case .wrongPassword: String(localized: "The password is incorrect.")
            }
        }
    }

    private static let keyAccount = "vault.master-key.v1"
    private static let cachedKey = Mutex<SymmetricKey?>(nil)

    /// Returns the vault key, creating it on first use.
    static func key() throws -> SymmetricKey {
        try cachedKey.withLock { cached in
            if let cached { return cached }
            let key: SymmetricKey
            if let data = try Keychain.read(keyAccount) {
                key = SymmetricKey(data: data)
            } else {
                key = SymmetricKey(size: .bits256)
                try Keychain.write(key.withUnsafeBytes { Data($0) }, account: keyAccount, synchronizable: FeatureFlags.syncKeyThroughICloudKeychain)
            }
            cached = key
            return key
        }
    }

    /// Moves the key into (or out of) iCloud Keychain when iCloud sync is turned
    /// on or off, so other devices signed in to the same Apple Account can read
    /// synced documents. Returns the previous key if a different key already
    /// existed in iCloud Keychain and was adopted; the caller must then
    /// re-encrypt local data from the returned key to the new one.
    static func prepareKeyForSync(_ enabled: Bool) throws -> SymmetricKey? {
        let local = try key()
        if enabled {
            if let remote = try Keychain.read(keyAccount, synchronizable: true) {
                guard remote != local.withUnsafeBytes({ Data($0) }) else { return nil }
                let remoteKey = SymmetricKey(data: remote)
                Keychain.delete(keyAccount)
                try Keychain.write(remote, account: keyAccount, synchronizable: true)
                cachedKey.withLock { $0 = remoteKey }
                return local
            }
            try Keychain.write(local.withUnsafeBytes { Data($0) }, account: keyAccount, synchronizable: true)
        } else {
            try Keychain.write(local.withUnsafeBytes { Data($0) }, account: keyAccount, synchronizable: false)
        }
        return nil
    }

    /// Re-encrypts `data` from `oldKey` to the current key.
    static func reseal(_ data: Data, from oldKey: SymmetricKey) throws -> Data {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: oldKey)
        return try seal(plain)
    }

    /// Forgets the in-memory copy of the key (on lock), so it has to be read
    /// from the Keychain again.
    static func purgeCachedKey() {
        cachedKey.withLock { $0 = nil }
    }

    static func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key())
        guard let combined = box.combined else { throw Error.keyUnavailable }
        return combined
    }

    static func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key())
    }

    static func seal<T: Encodable>(_ value: T) throws -> Data {
        try seal(JSONEncoder.vault.encode(value))
    }

    static func open<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder.vault.decode(type, from: open(data))
    }

    // MARK: Password-based encryption (backups and exports)

    private static let backupMagic = Data("VAULTBK1".utf8)
    private static let pbkdfRounds: UInt32 = 600_000

    /// Encrypts `data` with a key derived from `password` (PBKDF2-SHA256,
    /// 600,000 rounds, random salt), so a backup can be restored on a new iPhone.
    static func seal(_ data: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let key = try deriveKey(password: password, salt: salt)
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw Error.keyUnavailable }
        return backupMagic + salt + combined
    }

    static func open(_ data: Data, password: String) throws -> Data {
        guard data.count > backupMagic.count + 16, data.prefix(backupMagic.count) == backupMagic else {
            throw Error.invalidBackup
        }
        let salt = data.dropFirst(backupMagic.count).prefix(16)
        let body = data.dropFirst(backupMagic.count + 16)
        let key = try deriveKey(password: password, salt: Data(salt))
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: body), using: key)
        } catch {
            throw Error.wrongPassword
        }
    }

    static func isBackup(_ data: Data) -> Bool {
        data.prefix(backupMagic.count) == backupMagic
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), pbkdfRounds,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw Error.keyUnavailable }
        return SymmetricKey(data: derived)
    }
}
