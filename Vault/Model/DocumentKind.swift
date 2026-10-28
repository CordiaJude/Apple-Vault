import Foundation

/// A built-in document template: its name, symbol, default color and category,
/// the fields it carries, and how Vault reminds you before it expires.
nonisolated enum DocumentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case passport
    case driversLicense
    case stateID
    case healthInsurance
    case dentalInsurance
    case visionInsurance
    case autoInsurance
    case homeInsurance
    case vehicleRegistration
    case birthCertificate
    case socialSecurityCard
    case marriageCertificate
    case visa
    case residencePermit
    case greenCard
    case vaccinationRecord
    case membershipCard
    case warranty
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .passport: String(localized: "Passport")
        case .driversLicense: String(localized: "Driver’s License")
        case .stateID: String(localized: "State ID")
        case .healthInsurance: String(localized: "Health Insurance")
        case .dentalInsurance: String(localized: "Dental Insurance")
        case .visionInsurance: String(localized: "Vision Insurance")
        case .autoInsurance: String(localized: "Auto Insurance")
        case .homeInsurance: String(localized: "Home or Renters Insurance")
        case .vehicleRegistration: String(localized: "Vehicle Registration")
        case .birthCertificate: String(localized: "Birth Certificate")
        case .socialSecurityCard: String(localized: "Social Security Card")
        case .marriageCertificate: String(localized: "Marriage Certificate")
        case .visa: String(localized: "Visa")
        case .residencePermit: String(localized: "Residence Permit")
        case .greenCard: String(localized: "Green Card")
        case .vaccinationRecord: String(localized: "Vaccination Record")
        case .membershipCard: String(localized: "Membership Card")
        case .warranty: String(localized: "Warranty or Receipt")
        case .custom: String(localized: "Custom")
        }
    }

    var symbol: String {
        switch self {
        case .passport: "globe.americas.fill"
        case .driversLicense: "car.fill"
        case .stateID: "person.text.rectangle.fill"
        case .healthInsurance: "cross.case.fill"
        case .dentalInsurance: "mouth.fill"
        case .visionInsurance: "eyeglasses"
        case .autoInsurance: "car.side.fill"
        case .homeInsurance: "house.fill"
        case .vehicleRegistration: "doc.text.fill"
        case .birthCertificate: "figure.and.child.holdinghands"
        case .socialSecurityCard: "person.badge.shield.checkmark.fill"
        case .marriageCertificate: "heart.text.square.fill"
        case .visa: "airplane"
        case .residencePermit: "building.columns.fill"
        case .greenCard: "checkmark.seal.fill"
        case .vaccinationRecord: "syringe.fill"
        case .membershipCard: "star.circle.fill"
        case .warranty: "receipt.fill"
        case .custom: "doc.fill"
        }
    }

    var defaultColor: CardColor {
        switch self {
        case .passport: .indigo
        case .driversLicense, .stateID: .blue
        case .healthInsurance: .teal
        case .dentalInsurance: .sky
        case .visionInsurance: .mint
        case .autoInsurance: .orange
        case .homeInsurance: .brown
        case .vehicleRegistration: .graphite
        case .birthCertificate: .pink
        case .socialSecurityCard: .sky
        case .marriageCertificate: .red
        case .visa, .residencePermit: .purple
        case .greenCard: .green
        case .vaccinationRecord: .green
        case .membershipCard: .yellow
        case .warranty: .graphite
        case .custom: .blue
        }
    }

    var category: BuiltInCategory {
        switch self {
        case .passport, .visa, .residencePermit, .greenCard: .travel
        case .driversLicense, .stateID, .socialSecurityCard: .identity
        case .healthInsurance, .dentalInsurance, .visionInsurance, .vaccinationRecord: .health
        case .autoInsurance, .vehicleRegistration: .vehicles
        case .homeInsurance: .home
        case .birthCertificate, .marriageCertificate: .records
        case .membershipCard: .memberships
        case .warranty: .purchases
        case .custom: .other
        }
    }

    /// The fields a new document of this kind starts with.
    var fieldTemplates: [FieldTemplate] {
        switch self {
        case .passport:
            [
                .init(.fullName, "Name", .text),
                .init(.documentNumber, "Passport Number", .identifier, sensitive: true),
                .init(.nationality, "Nationality", .text),
                .init(.dateOfBirth, "Date of Birth", .date),
                .init(.issueDate, "Issue Date", .date),
                .init(.expiryDate, "Expiration Date", .date),
                .init(.placeOfIssue, "Place of Issue", .text),
            ]
        case .driversLicense, .stateID:
            [
                .init(.fullName, "Name", .text),
                .init(.documentNumber, self == .stateID ? "ID Number" : "License Number", .identifier, sensitive: true),
                .init(.state, "State", .text),
                .init(.licenseClass, "Class", .text),
                .init(.dateOfBirth, "Date of Birth", .date),
                .init(.issueDate, "Issue Date", .date),
                .init(.expiryDate, "Expiration Date", .date),
                .init(.restrictions, "Restrictions", .text),
            ]
        case .healthInsurance, .dentalInsurance, .visionInsurance:
            [
                .init(.provider, "Provider", .text),
                .init(.fullName, "Member Name", .text),
                .init(.memberID, "Member ID", .identifier, sensitive: true),
                .init(.groupNumber, "Group Number", .identifier),
                .init(.policyNumber, "Policy Number", .identifier),
                .init(.phone, "Phone", .phone),
                .init(.renewalDate, "Renewal Date", .date),
            ]
        case .autoInsurance, .homeInsurance:
            [
                .init(.provider, "Provider", .text),
                .init(.fullName, "Policyholder", .text),
                .init(.policyNumber, "Policy Number", .identifier, sensitive: true),
                .init(.memberID, "Member ID", .identifier),
                .init(.groupNumber, "Group Number", .identifier),
                .init(.phone, "Claims Phone", .phone),
                .init(.renewalDate, "Renewal Date", .date),
            ]
        case .vehicleRegistration:
            [
                .init(.plate, "License Plate", .identifier),
                .init(.vin, "VIN", .identifier, sensitive: true),
                .init(.vehicle, "Vehicle", .text),
                .init(.state, "State", .text),
                .init(.expiryDate, "Expiration Date", .date),
            ]
        case .birthCertificate:
            [
                .init(.fullName, "Name", .text),
                .init(.dateOfBirth, "Date of Birth", .date),
                .init(.placeOfBirth, "Place of Birth", .text),
                .init(.documentNumber, "Certificate Number", .identifier, sensitive: true),
                .init(.issuer, "Issued By", .text),
            ]
        case .socialSecurityCard:
            [
                .init(.fullName, "Name", .text),
                .init(.documentNumber, "Social Security Number", .identifier, sensitive: true),
            ]
        case .marriageCertificate:
            [
                .init(.spouseOne, "Spouse", .text),
                .init(.spouseTwo, "Spouse", .text),
                .init(.issueDate, "Date of Marriage", .date),
                .init(.placeOfIssue, "Place of Marriage", .text),
                .init(.documentNumber, "Certificate Number", .identifier, sensitive: true),
            ]
        case .visa, .residencePermit, .greenCard:
            [
                .init(.fullName, "Name", .text),
                .init(.documentNumber, self == .greenCard ? "USCIS Number" : "Document Number", .identifier, sensitive: true),
                .init(.visaType, self == .greenCard ? "Category" : "Type", .text),
                .init(.issuingCountry, "Issuing Country", .text),
                .init(.issueDate, "Issue Date", .date),
                .init(.expiryDate, "Expiration Date", .date),
            ]
        case .vaccinationRecord:
            [
                .init(.fullName, "Name", .text),
                .init(.vaccine, "Vaccine", .text),
                .init(.issueDate, "Date Given", .date),
                .init(.provider, "Provider", .text),
                .init(.lotNumber, "Lot Number", .identifier),
                .init(.expiryDate, "Next Dose Due", .date),
            ]
        case .membershipCard:
            [
                .init(.provider, "Organization", .text),
                .init(.fullName, "Member Name", .text),
                .init(.memberID, "Member Number", .identifier),
                .init(.expiryDate, "Expiration Date", .date),
            ]
        case .warranty:
            [
                .init(.product, "Product", .text),
                .init(.store, "Store", .text),
                .init(.purchaseDate, "Purchase Date", .date),
                .init(.price, "Price", .text),
                .init(.serialNumber, "Serial Number", .identifier),
                .init(.expiryDate, "Warranty Ends", .date),
            ]
        case .custom:
            []
        }
    }

    /// Whether documents of this kind usually expire.
    var usuallyExpires: Bool {
        switch self {
        case .birthCertificate, .socialSecurityCard, .marriageCertificate, .custom: false
        default: true
        }
    }

    /// Default reminders before expiry. Many countries require six months of
    /// passport validity to enter, so passports get earlier warnings.
    var defaultReminders: [ReminderOffset] {
        switch self {
        case .passport: [.init(9, .months), .init(6, .months)]
        default: [.init(60, .days), .init(14, .days)]
        }
    }

    /// The official renewal site, where an obvious one exists. Users can edit it.
    var defaultRenewalURL: URL? {
        switch self {
        case .passport: URL(string: "https://travel.state.gov/content/travel/en/passports/have-passport/renew.html")
        case .greenCard: URL(string: "https://www.uscis.gov/green-card/after-we-grant-your-green-card/replace-your-green-card")
        case .socialSecurityCard: URL(string: "https://www.ssa.gov/number-card/replace-card")
        case .driversLicense, .stateID: URL(string: "https://www.usa.gov/state-motor-vehicle-services")
        default: nil
        }
    }

    /// Document kinds whose primary number is especially sensitive.
    var isHighlySensitive: Bool {
        switch self {
        case .passport, .socialSecurityCard, .greenCard, .visa, .residencePermit, .birthCertificate: true
        default: false
        }
    }

    /// ID-1 cards (licenses, insurance cards) versus larger paper documents.
    var isCardSized: Bool {
        switch self {
        case .birthCertificate, .marriageCertificate, .vaccinationRecord, .warranty, .vehicleRegistration: false
        default: true
        }
    }
}

/// Default categories. People can add their own in Settings.
nonisolated enum BuiltInCategory: String, CaseIterable, Codable, Sendable {
    case identity, travel, health, vehicles, home, records, memberships, purchases, other

    var name: String {
        switch self {
        case .identity: String(localized: "Identity")
        case .travel: String(localized: "Travel")
        case .health: String(localized: "Health")
        case .vehicles: String(localized: "Vehicles")
        case .home: String(localized: "Home")
        case .records: String(localized: "Records")
        case .memberships: String(localized: "Memberships")
        case .purchases: String(localized: "Purchases")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .identity: "person.text.rectangle"
        case .travel: "airplane"
        case .health: "heart.text.square"
        case .vehicles: "car"
        case .home: "house"
        case .records: "doc.text"
        case .memberships: "star"
        case .purchases: "bag"
        case .other: "folder"
        }
    }
}
