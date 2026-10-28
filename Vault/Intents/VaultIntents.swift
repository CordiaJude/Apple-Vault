import AppIntents
import Foundation

/// Document types people ask Siri about, with the words they actually use.
enum SpokenDocumentKind: String, AppEnum {
    case passport, driversLicense, insuranceCard, dentalInsurance, visionInsurance, autoInsurance
    case vehicleRegistration, greenCard, visa, membershipCard, vaccinationRecord

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Document Type"
    static let caseDisplayRepresentations: [SpokenDocumentKind: DisplayRepresentation] = [
        .passport: DisplayRepresentation(title: "Passport", synonyms: ["passport"]),
        .driversLicense: DisplayRepresentation(title: "Driver’s License", synonyms: ["license", "driver's license", "drivers license", "ID"]),
        .insuranceCard: DisplayRepresentation(title: "Insurance Card", synonyms: ["insurance", "health insurance", "health insurance card", "medical card"]),
        .dentalInsurance: DisplayRepresentation(title: "Dental Insurance", synonyms: ["dental card"]),
        .visionInsurance: DisplayRepresentation(title: "Vision Insurance", synonyms: ["vision card"]),
        .autoInsurance: DisplayRepresentation(title: "Auto Insurance", synonyms: ["car insurance", "proof of insurance"]),
        .vehicleRegistration: DisplayRepresentation(title: "Vehicle Registration", synonyms: ["registration", "car registration"]),
        .greenCard: DisplayRepresentation(title: "Green Card", synonyms: ["permanent resident card"]),
        .visa: DisplayRepresentation(title: "Visa"),
        .membershipCard: DisplayRepresentation(title: "Membership Card", synonyms: ["membership", "loyalty card"]),
        .vaccinationRecord: DisplayRepresentation(title: "Vaccination Record", synonyms: ["vaccine card", "immunization record"]),
    ]

    var kinds: [String] {
        switch self {
        case .passport: [DocumentKind.passport.rawValue]
        case .driversLicense: [DocumentKind.driversLicense.rawValue, DocumentKind.stateID.rawValue]
        case .insuranceCard: [DocumentKind.healthInsurance.rawValue, DocumentKind.dentalInsurance.rawValue, DocumentKind.visionInsurance.rawValue]
        case .dentalInsurance: [DocumentKind.dentalInsurance.rawValue]
        case .visionInsurance: [DocumentKind.visionInsurance.rawValue]
        case .autoInsurance: [DocumentKind.autoInsurance.rawValue]
        case .vehicleRegistration: [DocumentKind.vehicleRegistration.rawValue]
        case .greenCard: [DocumentKind.greenCard.rawValue]
        case .visa: [DocumentKind.visa.rawValue, DocumentKind.residencePermit.rawValue]
        case .membershipCard: [DocumentKind.membershipCard.rawValue]
        case .vaccinationRecord: [DocumentKind.vaccinationRecord.rawValue]
        }
    }

    /// The best match in the vault: yours first, favorites first.
    func bestMatch(in snapshot: VaultSnapshot) -> VaultSnapshot.Item? {
        snapshot.items
            .filter { kinds.contains($0.kind) }
            .sorted { lhs, rhs in
                let l = (lhs.belongsToMe == true ? 0 : 1, lhs.isFavorite ? 0 : 1, kinds.firstIndex(of: lhs.kind) ?? 0)
                let r = (rhs.belongsToMe == true ? 0 : 1, rhs.isFavorite ? 0 : 1, kinds.firstIndex(of: rhs.kind) ?? 0)
                return l < r
            }
            .first
    }
}

/// "Show my insurance card" — opens Vault in Present mode, after Face ID.
struct ShowDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Document"
    static let description = IntentDescription("Shows a document full screen, ready to hand over. Vault asks for Face ID first.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Document Type")
    var kind: SpokenDocumentKind

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = VaultSnapshot.load()
        guard let item = kind.bestMatch(in: snapshot) else {
            return .result(dialog: "You don’t have a \(kind.localizedName) in Vault yet.")
        }
        ExternalRouteCenter.shared.pending = .present(item.id)
        return .result(dialog: "Opening your \(item.title).")
    }
}

/// "When does my passport expire?" — answered from names and dates only.
struct ExpirationDateIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Expiration Date"
    static let description = IntentDescription("Tells you when a document expires. Only the date is shared, never the document number.")

    @Parameter(title: "Document Type")
    var kind: SpokenDocumentKind

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Date?> {
        let snapshot = VaultSnapshot.load()
        guard let item = kind.bestMatch(in: snapshot) else {
            return .result(value: nil, dialog: "You don’t have a \(kind.localizedName) in Vault yet.")
        }
        guard let date = item.expiresOn else {
            return .result(value: nil, dialog: "Your \(item.title) doesn’t have an expiration date in Vault.")
        }
        let formatted = date.formatted(date: .long, time: .omitted)
        let status: IntentDialog = date < Calendar.current.startOfDay(for: .now)
            ? "Your \(item.title) expired on \(formatted)."
            : "Your \(item.title) expires on \(formatted)."
        return .result(value: date, dialog: status)
    }
}

/// "Open Vault".
struct OpenVaultIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Vault"
    static let description = IntentDescription("Opens Vault.")
    static let supportedModes: IntentModes = .foreground

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ExternalRouteCenter.shared.pending = .documents
        return .result()
    }
}

/// Phrases that work with no setup in Siri, Spotlight and Shortcuts.
struct VaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowDocumentIntent(),
            phrases: [
                "Show my \(\.$kind) in \(.applicationName)",
                "Show my \(\.$kind) from \(.applicationName)",
                "Open my \(\.$kind) in \(.applicationName)",
            ],
            shortTitle: "Show Document",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: ExpirationDateIntent(),
            phrases: [
                "When does my \(\.$kind) expire in \(.applicationName)",
                "Check my \(\.$kind) expiration in \(.applicationName)",
            ],
            shortTitle: "Expiration Date",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: OpenVaultIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my documents in \(.applicationName)",
            ],
            shortTitle: "Open Vault",
            systemImageName: "lock.shield"
        )
    }
}

extension SpokenDocumentKind {
    var localizedName: String {
        String(localized: Self.caseDisplayRepresentations[self]?.title ?? "document")
    }
}
