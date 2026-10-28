import AppIntents
import Foundation

/// A document as Siri, Shortcuts and the Control Center control see it.
///
/// Entities are built from `VaultSnapshot`, so they only ever carry a
/// document's name, kind, owner and expiration date.
nonisolated struct DocumentEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Document",
        numericFormat: "\(placeholder: .int) documents"
    )
    static let defaultQuery = DocumentEntityQuery()

    var id: UUID
    var title: String
    var kindName: String
    var symbol: String
    var personName: String?
    var expiresOn: Date?

    init(item: VaultSnapshot.Item) {
        id = item.id
        title = item.title
        kindName = item.kindName
        symbol = item.symbol
        personName = item.personName
        expiresOn = item.expiresOn
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = [personName, kindName].compactMap { $0 }.joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: symbol)
        )
    }
}

nonisolated struct DocumentEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [DocumentEntity.ID]) async throws -> [DocumentEntity] {
        let items = VaultSnapshot.load().items
        return identifiers.compactMap { id in items.first { $0.id == id }.map(DocumentEntity.init) }
    }

    func entities(matching string: String) async throws -> [DocumentEntity] {
        VaultSnapshot.load().items
            .filter {
                $0.title.localizedStandardContains(string)
                    || $0.kindName.localizedStandardContains(string)
                    || ($0.personName?.localizedStandardContains(string) ?? false)
            }
            .map(DocumentEntity.init)
    }

    func suggestedEntities() async throws -> [DocumentEntity] {
        VaultSnapshot.load().items
            .sorted { ($0.isFavorite ? 0 : 1, $0.title) < ($1.isFavorite ? 0 : 1, $1.title) }
            .map(DocumentEntity.init)
    }
}
