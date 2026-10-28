import Foundation
import UIKit

/// Picks up files left by the "Save to Vault" Share extension. They wait in
/// the App Group (Data Protection: Complete) until Vault is unlocked, then are
/// reviewed, encrypted into the vault and deleted from the inbox.
@MainActor
enum InboxImporter {
    struct Item: Identifiable {
        var manifest: InboxManifest
        var folder: URL
        var pages: [PageSource]
        var id: UUID { manifest.id }
    }

    static func checkForPendingItems(router: AppRouter) {
        guard !pendingFolders().isEmpty else { return }
        router.pendingInboxImport = true
    }

    static func pendingFolders() -> [URL] {
        guard let inbox = AppGroup.inboxURL,
              let folders = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        else { return [] }
        return folders.filter { FileManager.default.fileExists(atPath: $0.appending(path: InboxManifest.fileName).path(percentEncoded: false)) }
    }

    static func loadItems() -> [Item] {
        pendingFolders().compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: InboxManifest.fileName)),
                  let manifest = try? JSONDecoder.vault.decode(InboxManifest.self, from: data)
            else {
                try? FileManager.default.removeItem(at: folder)
                return nil
            }
            let pages: [PageSource] = manifest.files.compactMap { file in
                guard let data = try? Data(contentsOf: folder.appending(path: file.name)) else { return nil }
                return file.isPDF ? .pdf(data) : UIImage(data: data).map(PageSource.image)
            }
            return Item(manifest: manifest, folder: folder, pages: pages)
        }
        .sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    static func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.folder)
    }
}
