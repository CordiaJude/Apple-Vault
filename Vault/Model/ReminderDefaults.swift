import Foundation

/// The default reminder schedule, adjustable in Settings ▸ Reminders.
nonisolated enum ReminderDefaults {
    static func offsets(for kind: DocumentKind) -> [ReminderOffset] {
        kind == .passport ? passport : other
    }

    static var passport: [ReminderOffset] {
        get { read(SettingsKey.passportReminders) ?? DocumentKind.passport.defaultReminders }
        set { write(newValue, SettingsKey.passportReminders) }
    }

    static var other: [ReminderOffset] {
        get { read(SettingsKey.otherReminders) ?? DocumentKind.driversLicense.defaultReminders }
        set { write(newValue, SettingsKey.otherReminders) }
    }

    /// The hour of day reminders arrive (default 9 AM).
    static var hour: Int {
        get { UserDefaults.standard.object(forKey: SettingsKey.reminderHour) as? Int ?? 9 }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.reminderHour) }
    }

    private static func read(_ key: String) -> [ReminderOffset]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode([ReminderOffset].self, from: data))?.sorted(by: >)
    }

    private static func write(_ value: [ReminderOffset], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value.sorted(by: >)), forKey: key)
    }
}
