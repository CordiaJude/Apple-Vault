import Foundation
import os
import UserNotifications

/// Schedules local expiration reminders. Notifications name the document and
/// the date only, never numbers.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.vault", category: "reminders")
    private static let prefix = "vault.expiry."

    /// Asks for permission the first time a document with an expiration date
    /// is saved, rather than at launch.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default: return false
        }
    }

    func reschedule(for documents: [VaultDocument]) async {
        let wanted = documents.flatMap(requests(for:))
        let needsPermission = !wanted.isEmpty
        guard !needsPermission || (await requestAuthorizationIfNeeded()) else { return }

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        // iOS keeps at most 64 pending notifications per app; keep the soonest.
        let soonest = wanted.sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }.prefix(60)
        for item in soonest {
            do {
                try await center.add(item.request)
            } catch {
                logger.error("Could not schedule reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel(documentID: UUID) {
        Task {
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix + documentID.uuidString) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private struct Scheduled {
        var request: UNNotificationRequest
        var fireDate: Date?
    }

    private func requests(for document: VaultDocument) -> [Scheduled] {
        guard document.remindersEnabled, let expiry = document.expiresOn else { return [] }
        let calendar = Calendar.current
        let now = Date.now
        var results: [Scheduled] = []
        var offsets = document.reminderOffsets.map { Optional($0) }
        offsets.append(nil) // also on the day itself
        for offset in offsets {
            let day = offset.map { $0.fireDate(before: expiry) } ?? expiry
            guard let day,
                  var fire = calendar.date(bySettingHour: ReminderDefaults.hour, minute: 0, second: 0, of: day),
                  fire > now
            else { continue }
            fire = max(fire, now.addingTimeInterval(60))

            let content = UNMutableNotificationContent()
            let owner = document.person.map { $0.relationship == .me ? nil : $0.firstName } ?? nil
            let name = owner.map { String(localized: "\($0)’s \(document.title)") } ?? document.title
            let date = expiry.formatted(date: .long, time: .omitted)
            if offset == nil {
                content.title = String(localized: "\(name) expires today")
                content.body = String(localized: "Open Vault to see how to renew it.")
            } else if expiry < now {
                continue
            } else {
                content.title = String(localized: "\(name) expires soon")
                content.body = String(localized: "It expires on \(date).")
            }
            if document.kind == .passport, let offset, offset.approximateDays >= 150 {
                content.body += " " + String(localized: "Many countries require 6 months of passport validity to enter.")
            }
            content.sound = .default
            content.threadIdentifier = "expirations"
            content.userInfo = ["url": DeepLink.document(document.id).url.absoluteString]

            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let identifier = Self.prefix + document.id.uuidString + "." + (offset?.id ?? "day-of")
            results.append(Scheduled(request: UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), fireDate: fire))
        }
        return results
    }
}
