import Foundation

/// Describes one "Save to Vault" hand-off from the Share extension. Files sit in
/// `Inbox/<id>/` (Data Protection: Complete) until the app imports and encrypts
/// them, then the folder is deleted.
nonisolated struct InboxManifest: Codable, Sendable {
    nonisolated struct File: Codable, Sendable {
        var name: String
        var isPDF: Bool
    }

    var id: UUID
    var title: String
    var kind: String?
    var files: [File]
    var link: URL?
    var createdAt: Date

    static let fileName = "manifest.json"
}
