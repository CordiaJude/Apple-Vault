import Foundation

/// Compile-time and runtime switches.
///
/// iCloud sync needs a paid Apple Developer Program membership (CloudKit is not
/// available to free accounts), so it is compiled in only when
/// `VAULT_USE_CLOUDKIT = YES` in `Config/Signing.xcconfig`. Even then it stays
/// off until turned on in Settings.
nonisolated enum FeatureFlags {
    #if CLOUDKIT_SYNC
    static let cloudKitCompiledIn = true
    #else
    static let cloudKitCompiledIn = false
    #endif

    static var cloudKitContainer: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "VaultCloudKitContainer") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// Whether the person has turned on iCloud sync.
    static var iCloudSyncEnabled: Bool {
        cloudKitCompiledIn && UserDefaults.standard.bool(forKey: SettingsKey.iCloudSync)
    }

    /// With iCloud sync on, the vault key travels through iCloud Keychain
    /// (end-to-end encrypted) so your other devices can read synced documents.
    static var syncKeyThroughICloudKeychain: Bool { iCloudSyncEnabled }
}

/// UserDefaults keys for settings. Settings are preferences only; nothing
/// sensitive is ever stored in UserDefaults.
nonisolated enum SettingsKey {
    static let lockEnabled = "lockEnabled"
    static let autoLock = "autoLockTimeout"
    static let iCloudSync = "iCloudSyncEnabled"
    static let spotlight = "spotlightEnabled"
    static let passportReminders = "defaultPassportReminders"
    static let otherReminders = "defaultOtherReminders"
    static let reminderHour = "reminderHour"
    static let favoriteDocument = "favoriteDocumentID"
    static let didSeedSampleData = "didSeedSampleData"
    static let hasOnboarded = "hasOnboarded"
}
