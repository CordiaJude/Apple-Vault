import Foundation
import SwiftData
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let vaultBackup = UTType(exportedAs: "app.vault.backup", conformingTo: .data)
}

/// Encrypted full backups to a single file you can keep in Files, and restore
/// on this or another iPhone.
///
/// The file is encrypted with a password you choose (PBKDF2 + AES-256-GCM),
/// independent of this device's vault key, so it can be restored anywhere.
@MainActor
enum BackupService {
    // A self-contained, versioned archive format.
    nonisolated struct Archive: Codable, Sendable {
        var version = 1
        var createdAt = Date()
        var people: [PersonRecord]
        var categories: [CategoryRecord]
        var documents: [DocumentRecord]
    }

    nonisolated struct PersonRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var relationship: String
        var color: String
        var emoji: String
        var photo: Data?
        var sortOrder: Int
    }

    nonisolated struct CategoryRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var symbol: String
        var builtIn: String?
        var sortOrder: Int
    }

    nonisolated struct PageRecord: Codable, Sendable {
        var id: UUID
        var index: Int
        var role: String
        var isPDF: Bool
        var width: Double
        var height: Double
        var data: Data
        var thumbnail: Data?
    }

    nonisolated struct DocumentRecord: Codable, Sendable {
        var id: UUID
        var title: String
        var kind: String
        var color: String
        var tags: [String]
        var expiresOn: Date?
        var isFavorite: Bool
        var createdAt: Date
        var updatedAt: Date
        var renewalURL: String?
        var reminders: Data?
        var remindersEnabled: Bool
        var payload: DocumentPayload
        var personID: UUID?
        var categoryID: UUID?
        var pages: [PageRecord]
    }

    struct RestoreSummary {
        var documents: Int
        var people: Int
        var skipped: Int
    }

    // MARK: Backup

    static func makeBackup(context: ModelContext, password: String) throws -> URL {
        let people = try context.fetch(FetchDescriptor<Person>())
        let categories = try context.fetch(FetchDescriptor<DocumentCategory>())
        let documents = try context.fetch(FetchDescriptor<VaultDocument>())

        let archive = Archive(
            people: people.map { person in
                PersonRecord(
                    id: person.id, name: person.name, relationship: person.relationshipRaw, color: person.colorRaw,
                    emoji: person.emoji, photo: person.encryptedPhoto.flatMap { try? VaultCrypto.open($0) }, sortOrder: person.sortOrder
                )
            },
            categories: categories.map {
                CategoryRecord(id: $0.id, name: $0.name, symbol: $0.symbol, builtIn: $0.builtInRaw, sortOrder: $0.sortOrder)
            },
            documents: documents.map { document in
                DocumentRecord(
                    id: document.id, title: document.title, kind: document.kindRaw, color: document.colorRaw, tags: document.tags,
                    expiresOn: document.expiresOn, isFavorite: document.isFavorite, createdAt: document.createdAt,
                    updatedAt: document.updatedAt, renewalURL: document.renewalURLString, reminders: document.reminderOffsetsData,
                    remindersEnabled: document.remindersEnabled, payload: document.payload, personID: document.person?.id,
                    categoryID: document.category?.id,
                    pages: document.sortedPages.compactMap { page in
                        guard let data = page.data() else { return nil }
                        return PageRecord(
                            id: page.id, index: page.index, role: page.roleRaw, isPDF: page.isPDF, width: page.pixelWidth,
                            height: page.pixelHeight, data: data, thumbnail: page.encryptedThumbnail.flatMap { try? VaultCrypto.open($0) }
                        )
                    }
                )
            }
        )
        let plain = try JSONEncoder.vault.encode(archive)
        let sealed = try VaultCrypto.seal(plain, password: password)
        let name = String(localized: "Vault Backup \(Date.now.formatted(.iso8601.year().month().day())).vaultbackup")
        return try SecureFiles.writeTemporary(sealed, named: name)
    }

    // MARK: Restore

    /// Adds everything in the backup that isn't already in the vault.
    static func restore(from url: URL, password: String, context: ModelContext) throws -> RestoreSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let sealed = try Data(contentsOf: url)
        let archive = try JSONDecoder.vault.decode(Archive.self, from: VaultCrypto.open(sealed, password: password))

        let existingDocuments = Set(try context.fetch(FetchDescriptor<VaultDocument>()).map(\.id))
        var people = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Person>()).map { ($0.id, $0) })
        var categories = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DocumentCategory>()).map { ($0.id, $0) })
        let builtIns = Dictionary(categories.values.compactMap { c in c.builtInRaw.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })

        var addedPeople = 0
        for record in archive.people where people[record.id] == nil {
            // Merge "Me" into the existing "Me" rather than creating a second one.
            if record.relationship == Relationship.me.rawValue, let me = people.values.first(where: { $0.relationship == .me }) {
                people[record.id] = me
                continue
            }
            let person = Person(name: record.name, relationship: Relationship(rawValue: record.relationship) ?? .other,
                                color: CardColor(rawValue: record.color) ?? .blue, emoji: record.emoji, sortOrder: record.sortOrder)
            person.id = record.id
            person.encryptedPhoto = try record.photo.map(VaultCrypto.seal)
            context.insert(person)
            people[record.id] = person
            addedPeople += 1
        }
        for record in archive.categories where categories[record.id] == nil {
            if let builtIn = record.builtIn, let existing = builtIns[builtIn] {
                categories[record.id] = existing
                continue
            }
            let category = DocumentCategory(name: record.name, symbol: record.symbol, sortOrder: record.sortOrder)
            category.id = record.id
            context.insert(category)
            categories[record.id] = category
        }

        var added = 0
        var skipped = 0
        for record in archive.documents {
            guard !existingDocuments.contains(record.id) else { skipped += 1; continue }
            let document = VaultDocument(title: record.title, kind: DocumentKind(rawValue: record.kind) ?? .custom,
                                         color: CardColor(rawValue: record.color))
            document.id = record.id
            document.tags = record.tags
            document.isFavorite = record.isFavorite
            document.createdAt = record.createdAt
            document.renewalURLString = record.renewalURL
            document.reminderOffsetsData = record.reminders
            document.remindersEnabled = record.remindersEnabled
            context.insert(document)
            document.payload = record.payload
            document.expiresOn = record.expiresOn
            document.updatedAt = record.updatedAt
            document.person = record.personID.flatMap { people[$0] }
            document.category = record.categoryID.flatMap { categories[$0] }
            for pageRecord in record.pages {
                let page = DocumentPage(role: PageRole(rawValue: pageRecord.role) ?? .extra, index: pageRecord.index)
                page.id = pageRecord.id
                page.isPDF = pageRecord.isPDF
                page.pixelWidth = pageRecord.width
                page.pixelHeight = pageRecord.height
                page.encryptedData = try VaultCrypto.seal(pageRecord.data)
                page.encryptedThumbnail = try pageRecord.thumbnail.map(VaultCrypto.seal)
                context.insert(page)
                page.document = document
            }
            added += 1
        }
        try context.save()
        return RestoreSummary(documents: added, people: addedPeople, skipped: skipped)
    }
}
