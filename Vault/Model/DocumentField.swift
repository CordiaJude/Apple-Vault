import Foundation

/// Stable keys for well-known fields, so scanning, search and Siri can find
/// "the expiration date" regardless of how a field is labeled.
nonisolated enum FieldKey: String, Codable, Sendable, CaseIterable {
    case fullName, documentNumber, nationality, dateOfBirth, issueDate, expiryDate, placeOfIssue
    case state, licenseClass, restrictions
    case provider, memberID, groupNumber, policyNumber, phone, renewalDate
    case plate, vin, vehicle
    case placeOfBirth, issuer, spouseOne, spouseTwo
    case visaType, issuingCountry
    case vaccine, lotNumber
    case product, store, purchaseDate, price, serialNumber
    case custom
}

/// How a field's value is entered, displayed and copied.
nonisolated enum FieldKind: String, Codable, Sendable, CaseIterable {
    case text
    case identifier
    case date
    case phone
    case url

    var name: String {
        switch self {
        case .text: String(localized: "Text")
        case .identifier: String(localized: "Number")
        case .date: String(localized: "Date")
        case .phone: String(localized: "Phone")
        case .url: String(localized: "Link")
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .identifier: "number"
        case .date: "calendar"
        case .phone: "phone"
        case .url: "link"
        }
    }
}

nonisolated struct FieldTemplate: Sendable, Hashable {
    var key: FieldKey
    var label: String
    var kind: FieldKind
    var isSensitive: Bool

    init(_ key: FieldKey, _ label: String.LocalizationValue, _ kind: FieldKind, sensitive: Bool = false) {
        self.key = key
        self.label = String(localized: label)
        self.kind = kind
        self.isSensitive = sensitive
    }

    func makeField(value: String = "") -> DocumentField {
        DocumentField(key: key, label: label, value: value, kind: kind, isSensitive: isSensitive)
    }
}

/// One typed field on a document. Stored encrypted inside `DocumentPayload`.
nonisolated struct DocumentField: Codable, Sendable, Hashable, Identifiable {
    var id = UUID()
    var key: FieldKey
    var label: String
    var value: String
    var kind: FieldKind
    var isSensitive: Bool

    init(key: FieldKey = .custom, label: String, value: String = "", kind: FieldKind = .text, isSensitive: Bool = false) {
        self.key = key
        self.label = label
        self.value = value
        self.kind = kind
        self.isSensitive = isSensitive
    }

    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Date fields store ISO 8601 calendar dates ("2031-03-14").
    var dateValue: Date? {
        get { kind == .date ? DocumentField.parseDay(value) : nil }
        set { value = newValue.map(DocumentField.formatDay) ?? "" }
    }

    /// The value as people expect to read it.
    var displayValue: String {
        if kind == .date, let date = dateValue {
            return date.formatted(date: .long, time: .omitted)
        }
        return value
    }

    /// "•••• 4821" — enough to recognize, not enough to use.
    var maskedValue: String {
        let compact = value.filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count > 4 else { return String(repeating: "•", count: max(compact.count, 4)) }
        return "•••• " + compact.suffix(4)
    }

    /// Calendar days are stored as "yyyy-MM-dd" and interpreted in the
    /// current time zone, so a passport that expires on March 14 always shows
    /// March 14 wherever you travel.
    static func formatDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// When to remind before a document expires.
nonisolated struct ReminderOffset: Codable, Sendable, Hashable, Identifiable, Comparable {
    nonisolated enum Unit: String, Codable, Sendable, CaseIterable {
        case days, weeks, months

        var component: Calendar.Component {
            switch self {
            case .days: .day
            case .weeks: .weekOfYear
            case .months: .month
            }
        }
    }

    var value: Int
    var unit: Unit

    init(_ value: Int, _ unit: Unit) {
        self.value = value
        self.unit = unit
    }

    var id: String { "\(value)\(unit.rawValue)" }

    var approximateDays: Int {
        switch unit {
        case .days: value
        case .weeks: value * 7
        case .months: value * 30
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.approximateDays < rhs.approximateDays }

    /// "6 months before", "2 weeks before", "1 day before"
    var description: String {
        let duration: String = switch unit {
        case .days: value == 1 ? String(localized: "1 day") : String(localized: "\(value) days")
        case .weeks: value == 1 ? String(localized: "1 week") : String(localized: "\(value) weeks")
        case .months: value == 1 ? String(localized: "1 month") : String(localized: "\(value) months")
        }
        return String(localized: "\(duration) before")
    }

    func fireDate(before expiry: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: unit.component, value: -value, to: expiry)
    }

    static let choices: [ReminderOffset] = [
        .init(1, .days), .init(3, .days), .init(7, .days), .init(14, .days), .init(30, .days),
        .init(60, .days), .init(90, .days), .init(4, .months), .init(6, .months), .init(9, .months), .init(12, .months),
    ]
}

/// Everything sensitive about a document, encrypted as a single blob with the
/// vault key: typed fields, notes and the text recognized from its scans.
nonisolated struct DocumentPayload: Codable, Sendable, Hashable {
    var fields: [DocumentField] = []
    var notes: String = ""
    var recognizedText: String = ""

    func field(_ key: FieldKey) -> DocumentField? {
        fields.first { $0.key == key && !$0.isEmpty }
    }

    func value(_ key: FieldKey) -> String? {
        field(key)?.value
    }
}
