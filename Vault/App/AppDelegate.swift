import SwiftUI
import UIKit
import UserNotifications

/// Bridges the few UIKit entry points SwiftUI doesn't cover: Home Screen
/// Quick Actions and taps on reminder notifications.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let link = QuickActions.deepLink(for: item) {
            ExternalRouteCenter.shared.pending = link
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // Show reminders even while Vault is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let string = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            if let string, let url = URL(string: string), let link = DeepLink(url: url) {
                ExternalRouteCenter.shared.pending = link
            }
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let link = QuickActions.deepLink(for: shortcutItem) else { return false }
        ExternalRouteCenter.shared.pending = link
        return true
    }
}
