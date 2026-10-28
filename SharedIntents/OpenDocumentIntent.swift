import AppIntents
import Foundation
import Observation

/// Hands routes from App Intents (Siri, Shortcuts, Control Center) to the app's
/// router. Lives here so the intents compile in both the app and the widget
/// extension; it is only ever read inside the app.
@MainActor @Observable
final class ExternalRouteCenter {
    static let shared = ExternalRouteCenter()
    var pending: DeepLink?
    private init() {}
}

/// Opens a specific document in Present mode. Vault always asks for Face ID
/// first, even if it was unlocked a moment ago.
struct OpenDocumentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Document"
    static let description = IntentDescription(
        "Opens a document in Vault, ready to show. Vault asks for Face ID first.",
        categoryName: "Documents"
    )

    @Parameter(title: "Document")
    var target: DocumentEntity

    init() {}

    init(document: DocumentEntity) {
        target = document
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ExternalRouteCenter.shared.pending = .present(target.id)
        return .result()
    }
}

/// The configuration for the Control Center control: which document it opens.
struct SelectDocumentControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Document"
    static let description = IntentDescription("Choose the document this control opens.")

    @Parameter(title: "Document")
    var document: DocumentEntity?

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}
