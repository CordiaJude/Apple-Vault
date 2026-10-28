import Foundation

/// The App Group shared by Vault, its widgets, its Control Center control and
/// the Share extension.
///
/// Only two kinds of data ever live here:
/// - `Snapshot.json`: document *names and dates* for widgets and Siri. Never
///   numbers, images, notes or recognized text.
/// - `Inbox/`: files handed to the Share extension, waiting for Vault to import
///   (and encrypt) them the next time it is unlocked.
///
/// If the App Group is not configured (for example when it is turned off in
/// `Config/Signing.xcconfig`), every accessor returns `nil` and callers degrade
/// gracefully.
nonisolated enum AppGroup {
    static var identifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "VaultAppGroupIdentifier") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var containerURL: URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    static var defaults: UserDefaults? {
        guard let identifier, isAvailable else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    static var inboxURL: URL? {
        containerURL?.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    static var snapshotURL: URL? {
        containerURL?.appending(path: "Snapshot.json", directoryHint: .notDirectory)
    }
}
