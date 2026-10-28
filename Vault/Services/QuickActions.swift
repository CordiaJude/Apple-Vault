import UIKit

/// Home Screen Quick Actions: Scan Document, Show Favorite, Expiring Soon.
@MainActor
enum QuickActions {
    static let scanType = "app.vault.scan"
    static let favoriteType = "app.vault.favorite"
    static let expiringType = "app.vault.expiring"

    static func update(documents: [VaultDocument]) {
        let favorite = Self.favorite(in: documents)
        var items = [
            UIApplicationShortcutItem(
                type: scanType,
                localizedTitle: String(localized: "Scan Document"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "doc.viewfinder")
            ),
            UIApplicationShortcutItem(
                type: expiringType,
                localizedTitle: String(localized: "Expiring Soon"),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "calendar.badge.clock")
            ),
        ]
        if let favorite {
            // Shown on the Home Screen, so the title only: no numbers.
            items.insert(
                UIApplicationShortcutItem(
                    type: favoriteType,
                    localizedTitle: String(localized: "Show Favorite"),
                    localizedSubtitle: favorite.title,
                    icon: UIApplicationShortcutIcon(systemImageName: "star.fill")
                ),
                at: 1
            )
        }
        UIApplication.shared.shortcutItems = items
    }

    static func favorite(in documents: [VaultDocument]) -> VaultDocument? {
        if let id = UserDefaults.standard.string(forKey: SettingsKey.favoriteDocument).flatMap(UUID.init(uuidString:)),
           let pinned = documents.first(where: { $0.id == id }) {
            return pinned
        }
        return documents.filter(\.isFavorite).sorted { $0.updatedAt > $1.updatedAt }.first
    }

    static func deepLink(for item: UIApplicationShortcutItem) -> DeepLink? {
        switch item.type {
        case scanType: .scan
        case favoriteType: .favorite
        case expiringType: .expiring
        default: nil
        }
    }
}
