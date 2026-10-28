import SwiftUI
import UIKit

/// Shows the lock screen and the App Switcher cover in their own window, above
/// every sheet, full-screen cover and alert, so no document can stay visible
/// behind a presented view when Vault locks.
@MainActor
final class PrivacyWindow {
    enum Content: Equatable {
        case hidden
        case cover
        case lock
    }

    private var window: UIWindow?
    private var hosting: UIHostingController<AnyView>?
    private(set) var content: Content = .hidden

    func update(_ content: Content, lock: AppLock) {
        guard content != self.content else { return }
        self.content = content
        switch content {
        case .hidden:
            window?.isHidden = true
            mainWindow?.makeKey()
        case .cover:
            present(AnyView(PrivacyCover()))
        case .lock:
            present(AnyView(LockView().environment(lock)))
        }
    }

    private var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private var mainWindow: UIWindow? {
        activeScene?.windows.first { $0 !== window && !$0.isHidden }
    }

    private func present(_ view: AnyView) {
        if window == nil, let scene = activeScene {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let hosting = UIHostingController(rootView: view)
            hosting.view.backgroundColor = .systemBackground
            window.rootViewController = hosting
            self.window = window
            self.hosting = hosting
        }
        hosting?.rootView = view
        window?.isHidden = false
        window?.makeKeyAndVisible()
    }
}
