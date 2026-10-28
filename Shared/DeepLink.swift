import Foundation

/// URLs that widgets, the Control Center control, Spotlight and Quick Actions
/// use to open Vault. Anything that reveals a document always requires a fresh
/// Face ID check inside the app.
nonisolated enum DeepLink: Hashable, Sendable {
    case documents
    case document(UUID)
    case present(UUID)
    case expiring
    case scan
    case favorite
    case search

    static let scheme = "vault"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .documents: components.host = "documents"
        case .document(let id): components.host = "document"; components.path = "/" + id.uuidString
        case .present(let id): components.host = "present"; components.path = "/" + id.uuidString
        case .expiring: components.host = "expiring"
        case .scan: components.host = "scan"
        case .favorite: components.host = "favorite"
        case .search: components.host = "search"
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let id = UUID(uuidString: url.lastPathComponent)
        switch host {
        case "documents": self = .documents
        case "document": guard let id else { return nil }; self = .document(id)
        case "present": guard let id else { return nil }; self = .present(id)
        case "expiring": self = .expiring
        case "scan": self = .scan
        case "favorite": self = .favorite
        case "search": self = .search
        default: return nil
        }
    }

    /// Whether following this link reveals document content.
    var revealsDocument: Bool {
        switch self {
        case .document, .present, .favorite: true
        default: false
        }
    }
}
