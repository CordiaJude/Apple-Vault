import EventKit
import Foundation

/// Adds a renewal reminder to the Reminders app.
@MainActor
enum RemindersService {
    enum Failure: LocalizedError {
        case accessDenied
        case noList

        var errorDescription: String? {
            switch self {
            case .accessDenied: String(localized: "Vault doesn’t have access to Reminders. You can allow it in Settings ▸ Apps ▸ Vault.")
            case .noList: String(localized: "There’s no Reminders list to add to.")
            }
        }
    }

    /// Creates "Renew <document>" due `leadDays` before expiry (or on the expiry
    /// date if that has already passed).
    static func addRenewalReminder(title: String, expiry: Date, leadDays: Int = 30, url: URL?) async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw Failure.accessDenied }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw Failure.noList }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = String(localized: "Renew \(title)")
        let lead = Calendar.current.date(byAdding: .day, value: -leadDays, to: expiry) ?? expiry
        let due = max(lead, Calendar.current.startOfDay(for: .now))
        var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
        components.hour = ReminderDefaults.hour
        reminder.dueDateComponents = components
        reminder.addAlarm(EKAlarm(absoluteDate: Calendar.current.date(from: components) ?? due))
        reminder.notes = String(localized: "Expires \(expiry.formatted(date: .long, time: .omitted)).")
        reminder.url = url
        try store.save(reminder, commit: true)
    }
}
