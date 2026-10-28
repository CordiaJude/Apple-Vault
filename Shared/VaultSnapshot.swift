import Foundation

/// A deliberately minimal, non-sensitive summary of the vault: document names,
/// kinds, owners and dates only. Widgets, the Control Center control and Siri
/// read this instead of the encrypted store, so they never touch document
/// numbers, images or notes, and work while the vault is locked.
nonisolated struct VaultSnapshot: Codable, Sendable {
    nonisolated struct Item: Codable, Sendable, Identifiable, Hashable {
        var id: UUID
        var title: String
        var kind: String
        var kindName: String
        var symbol: String
        var personName: String?
        var color: CardColor
        var expiresOn: Date?
        var isFavorite: Bool
        /// Whether it belongs to the person marked "Me" (so Siri picks your passport, not your partner's).
        var belongsToMe: Bool?
    }

    var items: [Item]
    var generatedAt: Date

    static let empty = VaultSnapshot(items: [], generatedAt: .distantPast)

    /// Items with an expiration date, soonest first (already-expired items included).
    var expiringItems: [Item] {
        items.filter { $0.expiresOn != nil }.sorted { $0.expiresOn! < $1.expiresOn! }
    }

    /// The next item that has not expired yet, or the most recently expired one.
    var nextExpiring: Item? {
        let today = Calendar.current.startOfDay(for: .now)
        return expiringItems.first { $0.expiresOn! >= today } ?? expiringItems.last
    }

    static func load() -> VaultSnapshot {
        guard let url = AppGroup.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.vault.decode(VaultSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save() throws {
        guard let url = AppGroup.snapshotURL else { return }
        let data = try JSONEncoder.vault.encode(self)
        // Widgets render on the Lock Screen, so this file (names and dates only)
        // stays readable after first unlock.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove() {
        guard let url = AppGroup.snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

nonisolated extension JSONEncoder {
    static var vault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

nonisolated extension JSONDecoder {
    static var vault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
