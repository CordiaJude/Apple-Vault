import Foundation

/// Helpers that make sure everything Vault writes to disk is protected with
/// Data Protection class Complete (unreadable while the iPhone is locked).
nonisolated enum SecureFiles {
    /// Creates `url` (if needed) and marks it Complete, so files created inside
    /// it, including SwiftData's store and external blobs, inherit the class.
    static func prepareDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        }
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Re-applies Complete protection to every file under `url`.
    static func protectContents(of url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in enumerator {
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path(percentEncoded: false))
        }
    }

    /// A scratch directory for exports and shares. Emptied on every launch and
    /// whenever Vault locks.
    static var temporaryDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "VaultExports", directoryHint: .isDirectory)
        try? prepareDirectory(url)
        return url
    }

    static func clearTemporaryFiles() {
        let url = FileManager.default.temporaryDirectory.appending(path: "VaultExports", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: url)
    }

    static func writeTemporary(_ data: Data, named name: String) throws -> URL {
        let folder = temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try prepareDirectory(folder)
        let url = folder.appending(path: name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
