import Foundation
import SwiftData
import UIKit

// All models follow CloudKit's rules (every property has a default value, every
// relationship is optional, no unique constraints) so iCloud sync can be turned
// on without a migration.

/// A family member who documents belong to.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var relationshipRaw: String = Relationship.me.rawValue
    var colorRaw: String = CardColor.blue.rawValue
    /// An emoji or Memoji-style character shown when there is no photo.
    var emoji: String = ""
    /// The avatar photo, encrypted with the vault key.
    @Attribute(.externalStorage) var encryptedPhoto: Data?
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \VaultDocument.person)
    var documents: [VaultDocument]? = []

    init(name: String, relationship: Relationship, color: CardColor, emoji: String = "", sortOrder: Int = 0) {
        self.name = name
        self.relationshipRaw = relationship.rawValue
        self.colorRaw = color.rawValue
        self.emoji = emoji
        self.sortOrder = sortOrder
    }

    var relationship: Relationship {
        get { Relationship(rawValue: relationshipRaw) ?? .other }
        set { relationshipRaw = newValue.rawValue }
    }

    var color: CardColor {
        get { CardColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var displayName: String {
        name.isEmpty ? relationship.name : name
    }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var photo: UIImage? {
        get {
            guard let encryptedPhoto, let data = try? VaultCrypto.open(encryptedPhoto) else { return nil }
            return UIImage(data: data)
        }
        set {
            encryptedPhoto = newValue
                .flatMap { $0.preparingThumbnail(of: CGSize(width: 512, height: 512)) ?? $0 }
                .flatMap { $0.jpegData(compressionQuality: 0.85) }
                .flatMap { try? VaultCrypto.seal($0) }
        }
    }

    var activeDocuments: [VaultDocument] {
        (documents ?? []).sorted { $0.sortKey < $1.sortKey }
    }
}

nonisolated enum Relationship: String, CaseIterable, Codable, Sendable, Identifiable {
    case me, partner, child, parent, sibling, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .me: String(localized: "Me")
        case .partner: String(localized: "Partner")
        case .child: String(localized: "Child")
        case .parent: String(localized: "Parent")
        case .sibling: String(localized: "Sibling")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .me: "person.crop.circle"
        case .partner: "heart"
        case .child: "figure.child"
        case .parent: "figure.2.and.child.holdinghands"
        case .sibling: "person.2"
        case .other: "person"
        }
    }
}

/// A user-visible group of documents (Identity, Travel, Health…).
@Model
final class DocumentCategory {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    var builtInRaw: String?
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \VaultDocument.category)
    var documents: [VaultDocument]? = []

    init(name: String, symbol: String, builtIn: BuiltInCategory? = nil, sortOrder: Int) {
        self.name = name
        self.symbol = symbol
        self.builtInRaw = builtIn?.rawValue
        self.sortOrder = sortOrder
    }

    var builtIn: BuiltInCategory? { builtInRaw.flatMap(BuiltInCategory.init) }
}

/// A document in the vault. Everything that identifies you (field values,
/// notes, recognized text, images and PDFs) is encrypted with the vault key.
/// Only what is needed to list, sort and remind (title, kind, color, dates)
/// is stored in the clear, and even that sits in a database protected by
/// Data Protection "Complete".
@Model
final class VaultDocument {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = DocumentKind.custom.rawValue
    var colorRaw: String = CardColor.blue.rawValue
    var tags: [String] = []
    var expiresOn: Date?
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var renewalURLString: String?
    /// Encoded `[ReminderOffset]`; `nil` means "use the defaults for this kind".
    var reminderOffsetsData: Data?
    var remindersEnabled: Bool = true
    /// Encrypted `DocumentPayload` (fields, notes, recognized text).
    @Attribute(.externalStorage) var encryptedPayload: Data?

    var person: Person?
    var category: DocumentCategory?

    @Relationship(deleteRule: .cascade, inverse: \DocumentPage.document)
    var pages: [DocumentPage]? = []

    @Transient private var payloadCache: DocumentPayload? = nil

    init(title: String, kind: DocumentKind, color: CardColor? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.colorRaw = (color ?? kind.defaultColor).rawValue
        self.renewalURLString = kind.defaultRenewalURL?.absoluteString
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var color: CardColor {
        get { CardColor(rawValue: colorRaw) ?? kind.defaultColor }
        set { colorRaw = newValue.rawValue }
    }

    var sortKey: String {
        String(format: "%04d-", sortOrder) + title.lowercased()
    }

    /// Decrypted fields, notes and recognized text.
    var payload: DocumentPayload {
        get {
            if let payloadCache { return payloadCache }
            guard let encryptedPayload,
                  let decoded = try? VaultCrypto.open(DocumentPayload.self, from: encryptedPayload)
            else { return DocumentPayload() }
            payloadCache = decoded
            return decoded
        }
        set {
            payloadCache = newValue
            encryptedPayload = try? VaultCrypto.seal(newValue)
            if let expiry = newValue.field(.expiryDate)?.dateValue ?? newValue.field(.renewalDate)?.dateValue {
                expiresOn = expiry
            } else if newValue.fields.contains(where: { $0.key == .expiryDate || $0.key == .renewalDate }) {
                expiresOn = nil
            }
            updatedAt = .now
        }
    }

    /// Drops the decrypted copy from memory (called when Vault locks).
    func purgeDecryptedCache() {
        payloadCache = nil
    }

    var reminderOffsets: [ReminderOffset] {
        get {
            if let reminderOffsetsData, let offsets = try? JSONDecoder().decode([ReminderOffset].self, from: reminderOffsetsData) {
                return offsets.sorted(by: >)
            }
            return ReminderDefaults.offsets(for: kind)
        }
        set { reminderOffsetsData = try? JSONEncoder().encode(newValue.sorted(by: >)) }
    }

    var usesDefaultReminders: Bool { reminderOffsetsData == nil }

    var renewalURL: URL? {
        get { renewalURLString.flatMap { URL(string: $0) } }
        set { renewalURLString = newValue?.absoluteString }
    }

    var sortedPages: [DocumentPage] {
        (pages ?? []).sorted { ($0.role.order, $0.index) < ($1.role.order, $1.index) }
    }

    var frontPage: DocumentPage? { sortedPages.first { $0.role == .front } ?? sortedPages.first }
    var backPage: DocumentPage? { sortedPages.first { $0.role == .back } }
    var extraPages: [DocumentPage] {
        let front = frontPage
        return sortedPages.filter { $0.role == .extra && $0 !== front }
    }

    var expiryStatus: ExpiryStatus { ExpiryStatus(expiresOn: expiresOn) }

    /// The best one-line summary for a card: who it belongs to and when it expires.
    var subtitle: String {
        if let expiresOn {
            let date = expiresOn.formatted(.dateTime.month(.abbreviated).day().year())
            return expiryStatus == .expired
                ? String(localized: "Expired \(date)")
                : String(localized: "Expires \(date)")
        }
        return kind.name
    }

    func snapshotItem() -> VaultSnapshot.Item {
        VaultSnapshot.Item(
            id: id,
            title: title,
            kind: kindRaw,
            kindName: kind.name,
            symbol: kind.symbol,
            personName: person?.displayName,
            color: color,
            expiresOn: expiresOn,
            isFavorite: isFavorite,
            belongsToMe: person?.relationship == .me
        )
    }
}

/// One page of a document: an image (front, back or extra page) or a PDF.
@Model
final class DocumentPage {
    var id: UUID = UUID()
    var index: Int = 0
    var roleRaw: String = PageRole.front.rawValue
    var isPDF: Bool = false
    var pixelWidth: Double = 0
    var pixelHeight: Double = 0
    /// The image or PDF data, encrypted with the vault key.
    @Attribute(.externalStorage) var encryptedData: Data?
    /// A small JPEG preview, encrypted with the vault key.
    @Attribute(.externalStorage) var encryptedThumbnail: Data?
    var document: VaultDocument?

    init(role: PageRole, index: Int) {
        self.roleRaw = role.rawValue
        self.index = index
    }

    var role: PageRole {
        get { PageRole(rawValue: roleRaw) ?? .extra }
        set { roleRaw = newValue.rawValue }
    }

    var aspectRatio: CGFloat {
        pixelWidth > 0 && pixelHeight > 0 ? pixelWidth / pixelHeight : 1.586
    }

    func data() -> Data? {
        encryptedData.flatMap { try? VaultCrypto.open($0) }
    }

    func thumbnail() -> UIImage? {
        encryptedThumbnail.flatMap { try? VaultCrypto.open($0) }.flatMap(UIImage.init(data:))
    }

    func image() -> UIImage? {
        guard let data = data() else { return nil }
        return isPDF ? PDFRendering.firstPageImage(of: data) : UIImage(data: data)
    }
}

nonisolated enum PageRole: String, Codable, Sendable, CaseIterable {
    case front, back, extra

    var order: Int {
        switch self {
        case .front: 0
        case .back: 1
        case .extra: 2
        }
    }

    var name: String {
        switch self {
        case .front: String(localized: "Front")
        case .back: String(localized: "Back")
        case .extra: String(localized: "Page")
        }
    }
}

nonisolated enum ExpiryStatus: Sendable, Equatable {
    case none
    case expired
    case soon       // within 30 days
    case upcoming   // within 6 months
    case later

    init(expiresOn: Date?, now: Date = .now) {
        guard let expiresOn else { self = .none; return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if expiresOn < today {
            self = .expired
        } else if let soon = calendar.date(byAdding: .day, value: 30, to: today), expiresOn <= soon {
            self = .soon
        } else if let upcoming = calendar.date(byAdding: .month, value: 6, to: today), expiresOn <= upcoming {
            self = .upcoming
        } else {
            self = .later
        }
    }
}
