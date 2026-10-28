import SwiftData
import SwiftUI

/// App-wide navigation state: the selected tab, navigation paths, and the
/// sheets and covers that can be opened from anywhere (including Siri,
/// widgets, Control Center, Spotlight and Quick Actions).
@MainActor @Observable
final class AppRouter {
    enum Tab: Hashable {
        case documents, expiring, people, search
    }

    enum AddSource: String, Identifiable {
        case scan, photos, files, manual
        var id: String { rawValue }
    }

    var tab: Tab = .documents
    var documentsPath: [UUID] = []
    var expiringPath: [UUID] = []
    var peoplePath = NavigationPath()
    var searchPath: [UUID] = []

    var presentedDocumentID: UUID?
    var isShowingSettings = false
    var addSource: AddSource?
    /// Files waiting in the Share extension's inbox, ready for review.
    var pendingInboxImport = false

    /// A route that reveals a document and is waiting for Face ID.
    private(set) var pendingLink: DeepLink?

    func handle(_ link: DeepLink, lock: AppLock, store: VaultStore) {
        if link.revealsDocument {
            pendingLink = link
            lock.requireFreshAuthentication()
            if !lock.isLocked { performPending(store: store) }
        } else {
            perform(link, store: store)
        }
    }

    /// Runs the waiting route once the vault is unlocked.
    func performPending(store: VaultStore) {
        guard let link = pendingLink else { return }
        pendingLink = nil
        perform(link, store: store)
    }

    private func perform(_ link: DeepLink, store: VaultStore) {
        dismissModals()
        switch link {
        case .documents:
            tab = .documents
        case .document(let id):
            tab = .documents
            documentsPath = store.document(id: id) == nil ? [] : [id]
        case .present(let id):
            tab = .documents
            if store.document(id: id) != nil { presentedDocumentID = id }
        case .favorite:
            tab = .documents
            let all = (try? store.context?.fetch(FetchDescriptor<VaultDocument>())) ?? []
            if let favorite = QuickActions.favorite(in: all) { presentedDocumentID = favorite.id }
        case .expiring:
            tab = .expiring
            expiringPath = []
        case .scan:
            tab = .documents
            addSource = .scan
        case .search:
            tab = .search
        }
    }

    private func dismissModals() {
        isShowingSettings = false
        addSource = nil
        presentedDocumentID = nil
    }
}
