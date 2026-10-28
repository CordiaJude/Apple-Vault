import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Optional Spotlight indexing (off by default). Only the document's title and
/// kind are indexed, never field values, notes or recognized text. Opening a
/// result still requires Face ID.
@MainActor
enum SpotlightIndexer {
    private static let index = CSSearchableIndex(name: "VaultDocuments", protectionClass: .complete)
    private static let domain = "app.vault.documents"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.spotlight) }

    static func index(_ documents: [VaultDocument]) {
        let items = documents.map { document in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = document.title
            attributes.contentDescription = document.kind.name
            attributes.displayName = document.title
            return CSSearchableItem(uniqueIdentifier: document.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        // Items with the same identifier are replaced; deleted documents are
        // removed individually in `remove(documentID:)`.
        index.indexSearchableItems(items)
    }

    static func remove(documentID: UUID) {
        index.deleteSearchableItems(withIdentifiers: [documentID.uuidString])
    }

    static func removeAll() {
        index.deleteAllSearchableItems()
    }
}

extension SpotlightIndexer {
    static let activityType = CSSearchableItemActionType

    static func documentID(from activity: NSUserActivity) -> UUID? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:))
    }
}
