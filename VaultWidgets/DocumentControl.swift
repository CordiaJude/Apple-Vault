import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center (and Lock Screen / Action button) control that opens
/// straight to a chosen document, after Face ID.
struct DocumentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "app.vault.document-control", provider: Provider()) { value in
            ControlWidgetButton(action: OpenDocumentIntent(document: value.document ?? .placeholder)) {
                Label(value.document?.title ?? String(localized: "Choose Document"), systemImage: value.document?.symbol ?? "wallet.pass")
            }
        }
        .displayName("Open Document")
        .description("Opens a document in Vault, ready to show. Asks for Face ID first.")
        .promptsForUserConfiguration()
    }

    nonisolated struct Value: Sendable {
        var document: DocumentEntity?
    }

    nonisolated struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectDocumentControlIntent) -> Value {
            Value(document: configuration.document)
        }

        func currentValue(configuration: SelectDocumentControlIntent) async throws -> Value {
            // Re-read the title in case the document was renamed.
            guard let id = configuration.document?.id,
                  let item = VaultSnapshot.load().items.first(where: { $0.id == id })
            else { return Value(document: configuration.document) }
            return Value(document: DocumentEntity(item: item))
        }
    }
}

extension DocumentEntity {
    nonisolated static var placeholder: DocumentEntity {
        DocumentEntity(item: .init(id: UUID(), title: String(localized: "Document"), kind: "custom", kindName: "", symbol: "wallet.pass",
                                   personName: nil, color: .blue, expiresOn: nil, isFavorite: false))
    }
}
