import Foundation
import FoundationModels

/// Uses Apple Intelligence's on-device model, when this iPhone has it, to
/// classify a document and pull out its fields with guided generation. Nothing
/// leaves the device. Falls back silently when the model isn't available.
nonisolated enum IntelligenceExtractor {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func extract(from text: String) async -> ExtractedDocument? {
        guard isAvailable, !text.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You read text recognized from a scan of a personal document and identify what kind of \
            document it is and the values printed on it. Only use values that appear in the text. \
            Write dates as yyyy-MM-dd. Leave a field out if it is not present.
            """)
        do {
            let prompt = "Document text:\n" + String(text.prefix(3500))
            let response = try await session.respond(to: prompt, generating: GeneratedDocument.self)
            return response.content.extracted
        } catch {
            return nil
        }
    }
}

@Generable
nonisolated struct GeneratedDocument {
    @Guide(description: "The kind of document.", .anyOf([
        "passport", "driversLicense", "stateID", "healthInsurance", "dentalInsurance", "visionInsurance",
        "autoInsurance", "homeInsurance", "vehicleRegistration", "birthCertificate", "socialSecurityCard",
        "marriageCertificate", "visa", "residencePermit", "greenCard", "vaccinationRecord", "membershipCard",
        "warranty", "custom",
    ]))
    var kind: String

    @Guide(description: "A short, friendly title, for example 'Blue Cross Health Insurance' or 'Costco Membership'.")
    var title: String

    @Guide(description: "Values printed on the document.", .maximumCount(14))
    var fields: [GeneratedField]
}

@Generable
nonisolated struct GeneratedField {
    @Guide(description: "Which value this is.", .anyOf([
        "fullName", "documentNumber", "nationality", "dateOfBirth", "issueDate", "expiryDate", "placeOfIssue",
        "state", "licenseClass", "restrictions", "provider", "memberID", "groupNumber", "policyNumber", "phone",
        "renewalDate", "plate", "vin", "vehicle", "placeOfBirth", "issuer", "visaType", "issuingCountry",
        "vaccine", "lotNumber", "product", "store", "purchaseDate", "price", "serialNumber",
    ]))
    var key: String

    @Guide(description: "The value exactly as printed. Dates as yyyy-MM-dd.")
    var value: String
}

nonisolated extension GeneratedDocument {
    var extracted: ExtractedDocument {
        var values: [FieldKey: String] = [:]
        for field in fields {
            guard let key = FieldKey(rawValue: field.key) else { continue }
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if [.dateOfBirth, .issueDate, .expiryDate, .renewalDate, .purchaseDate].contains(key) {
                guard DocumentField.parseDay(value) != nil else { continue }
            }
            values[key] = value
        }
        return ExtractedDocument(
            kind: DocumentKind(rawValue: kind) ?? .custom,
            title: title.isEmpty ? nil : title,
            values: values,
            source: .intelligence,
            confidence: 0.8
        )
    }
}
