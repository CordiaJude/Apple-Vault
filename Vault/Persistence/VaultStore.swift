import CryptoKit
import Foundation
import os
import SwiftData
import UIKit

/// Owns the SwiftData container and everything that should happen after the
/// vault changes: refreshing widgets, rescheduling reminders, updating
/// Spotlight (if enabled).
@MainActor @Observable
final class VaultStore {
    enum State {
        case loading
        case ready(ModelContainer)
        case failed(String)
    }

    private(set) var state: State = .loading
    /// Bumps whenever the container is replaced (e.g. iCloud sync toggled), so
    /// views rebuild against the new container.
    private(set) var generation = 0

    private let logger = Logger(subsystem: "app.vault", category: "store")
    private var pendingRefresh: Task<Void, Never>?

    static let schema = Schema([Person.self, VaultDocument.self, DocumentPage.self, DocumentCategory.self])

    var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    var context: ModelContext? { container?.mainContext }

    static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Vault", directoryHint: .isDirectory)
    }

    func load() {
        guard container == nil else { return }
        do {
            let container = try makeContainer()
            state = .ready(container)
            generation += 1
            ensureBuiltInCategories(in: container.mainContext)
            #if DEBUG
            SampleData.seedIfNeeded(in: container.mainContext)
            #endif
            vaultDidChange(immediately: true)
        } catch {
            logger.error("Could not open the vault: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let directory = Self.storeDirectory
        try SecureFiles.prepareDirectory(directory)
        let url = directory.appending(path: "Vault.store")

        var cloudKit: ModelConfiguration.CloudKitDatabase = .none
        #if CLOUDKIT_SYNC
        if FeatureFlags.iCloudSyncEnabled, let identifier = FeatureFlags.cloudKitContainer {
            cloudKit = .private(identifier)
        }
        #endif
        let configuration = ModelConfiguration("Vault", schema: Self.schema, url: url, cloudKitDatabase: cloudKit)
        let container = try ModelContainer(for: Self.schema, configurations: configuration)
        SecureFiles.protectContents(of: directory)
        return container
    }

    /// Turns iCloud sync on or off by reopening the store with or without
    /// CloudKit. Only available when compiled with `CLOUDKIT_SYNC`.
    func setICloudSync(_ enabled: Bool) throws {
        guard FeatureFlags.cloudKitCompiledIn else { return }
        let oldKey = try VaultCrypto.prepareKeyForSync(enabled)
        UserDefaults.standard.set(enabled, forKey: SettingsKey.iCloudSync)
        if let oldKey, let context {
            try reencryptAll(in: context, from: oldKey)
        }
        try context?.save()
        state = .loading
        let container = try makeContainer()
        state = .ready(container)
        generation += 1
        vaultDidChange(immediately: true)
    }

    private func reencryptAll(in context: ModelContext, from oldKey: SymmetricKey) throws {
        for document in try context.fetch(FetchDescriptor<VaultDocument>()) {
            if let data = document.encryptedPayload { document.encryptedPayload = try VaultCrypto.reseal(data, from: oldKey) }
            document.purgeDecryptedCache()
            for page in document.pages ?? [] {
                if let data = page.encryptedData { page.encryptedData = try VaultCrypto.reseal(data, from: oldKey) }
                if let data = page.encryptedThumbnail { page.encryptedThumbnail = try VaultCrypto.reseal(data, from: oldKey) }
            }
        }
        for person in try context.fetch(FetchDescriptor<Person>()) {
            if let data = person.encryptedPhoto { person.encryptedPhoto = try VaultCrypto.reseal(data, from: oldKey) }
        }
    }

    // MARK: Changes

    /// Call after any edit. Saves, then (debounced) refreshes widgets,
    /// reminders and Spotlight.
    func vaultDidChange(immediately: Bool = false) {
        guard let context else { return }
        do {
            if context.hasChanges { try context.save() }
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled, let self, let context = self.context else { return }
            let documents = (try? context.fetch(FetchDescriptor<VaultDocument>())) ?? []
            SystemSync.refresh(documents: documents)
            await NotificationScheduler.shared.reschedule(for: documents)
        }
    }

    func delete(_ document: VaultDocument) {
        guard let context else { return }
        NotificationScheduler.shared.cancel(documentID: document.id)
        SpotlightIndexer.remove(documentID: document.id)
        if UserDefaults.standard.string(forKey: SettingsKey.favoriteDocument) == document.id.uuidString {
            UserDefaults.standard.removeObject(forKey: SettingsKey.favoriteDocument)
        }
        context.delete(document)
        vaultDidChange()
    }

    func delete(_ person: Person) {
        guard let context else { return }
        context.delete(person)
        vaultDidChange()
    }

    /// Drops decrypted copies of payloads from memory (called when Vault locks).
    func purgeDecryptedData() {
        guard let context else { return }
        for document in (try? context.fetch(FetchDescriptor<VaultDocument>())) ?? [] {
            document.purgeDecryptedCache()
        }
    }

    // MARK: Categories

    private func ensureBuiltInCategories(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<DocumentCategory>())) ?? []
        let present = Set(existing.compactMap(\.builtInRaw))
        for (index, category) in BuiltInCategory.allCases.enumerated() where !present.contains(category.rawValue) {
            context.insert(DocumentCategory(name: category.name, symbol: category.symbol, builtIn: category, sortOrder: index))
        }
        try? context.save()
    }

    func category(for builtIn: BuiltInCategory) -> DocumentCategory? {
        guard let context else { return nil }
        let raw = builtIn.rawValue
        let descriptor = FetchDescriptor<DocumentCategory>(predicate: #Predicate { $0.builtInRaw == raw })
        return try? context.fetch(descriptor).first
    }

    /// The person marked as "Me", creating them on first use.
    func me() -> Person? {
        guard let context else { return nil }
        let raw = Relationship.me.rawValue
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.relationshipRaw == raw })
        if let me = try? context.fetch(descriptor).first { return me }
        let me = Person(name: "", relationship: .me, color: .blue, emoji: "", sortOrder: 0)
        context.insert(me)
        return me
    }

    func document(id: UUID) -> VaultDocument? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<VaultDocument>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
