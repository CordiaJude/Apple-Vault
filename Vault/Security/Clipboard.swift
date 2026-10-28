import UIKit
import UniformTypeIdentifiers

/// Copies values without sending them to other devices (no Universal
/// Clipboard). Sensitive values expire from the clipboard after 60 seconds.
@MainActor
enum Clipboard {
    static let sensitiveLifetime: TimeInterval = 60

    static func copy(_ value: String, sensitive: Bool) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if sensitive {
            options[.expirationDate] = Date.now.addingTimeInterval(sensitiveLifetime)
        }
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: value]], options: options)
    }
}
