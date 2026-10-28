import Foundation

/// What Vault understood from a scan, before the person confirms it.
nonisolated struct ExtractedDocument: Sendable, Equatable {
    enum Source: String, Sendable {
        case mrz, text, intelligence
    }

    var kind: DocumentKind
    var title: String?
    /// Field values keyed by template field. Dates are "yyyy-MM-dd".
    var values: [FieldKey: String]
    var source: Source
    /// 0…1, how sure Vault is about `kind`.
    var confidence: Double

    static func empty(_ kind: DocumentKind = .custom) -> ExtractedDocument {
        ExtractedDocument(kind: kind, title: nil, values: [:], source: .text, confidence: 0)
    }

    /// Fills `values` that are still empty from `other`.
    func merged(with other: ExtractedDocument) -> ExtractedDocument {
        var result = self
        for (key, value) in other.values where (result.values[key] ?? "").isEmpty {
            result.values[key] = value
        }
        if result.title == nil { result.title = other.title }
        return result
    }
}

/// On-device heuristics that turn recognized text into a document type and
/// field values: labeled numbers, dates, names, VINs, phone numbers.
/// Used on every device; Apple Intelligence (when available) refines it.
nonisolated enum FieldExtractor {
    static func extract(from text: String, mrz: MRZResult? = nil) -> ExtractedDocument {
        if let mrz { return fromMRZ(mrz, text: text) }

        let upper = text.uppercased()
        let lines = upper.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let (kind, confidence) = classify(upper)
        var values: [FieldKey: String] = [:]

        // Dates, by the label on the same or the previous line.
        for (key, date) in labeledDates(lines) where values[key] == nil {
            values[key] = date
        }
        let allDates = lines.flatMap(dates(in:))
        let today = DocumentField.formatDay(Date())
        if values[.expiryDate] == nil, kind.usuallyExpires, kind != .warranty {
            values[.expiryDate] = allDates.filter { $0 > today }.max()
        }
        if values[.dateOfBirth] == nil, [.passport, .driversLicense, .stateID, .birthCertificate].contains(kind) {
            values[.dateOfBirth] = allDates.filter { $0 < "2015" }.min()
        }

        // Numbers.
        switch kind {
        case .driversLicense, .stateID:
            values[.documentNumber] = firstMatch(#"\b(?:DLN|DL|LIC(?:ENSE)?|ID)[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9][A-Z0-9 -]{4,18}[A-Z0-9])"#, in: upper)
                .map { $0.replacingOccurrences(of: " ", with: "") }
            values[.licenseClass] = firstMatch(#"\bCLASS[ \t]*[:.]?[ \t]*([A-Z0-9]{1,2})\b"#, in: upper)
            values[.restrictions] = firstMatch(#"\b(?:RESTR(?:ICTIONS)?|RSTR|REST)[ \t]*[:.]?[ \t]*([A-Z0-9]{1,8})\b"#, in: upper)
            values[.state] = usState(in: lines)
        case .healthInsurance, .dentalInsurance, .visionInsurance, .autoInsurance, .homeInsurance:
            values[.memberID] = firstMatch(#"\b(?:MEMBER|SUBSCRIBER|IDENTIFICATION|ID)[ \t]*(?:ID|NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9][A-Z0-9-]{4,20})"#, in: upper)
            values[.groupNumber] = firstMatch(#"\bGR(?:OU)?P[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9][A-Z0-9-]{2,15})"#, in: upper)
            values[.policyNumber] = firstMatch(#"\bPOLICY[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9][A-Z0-9-]{3,20})"#, in: upper)
            values[.phone] = phone(in: upper)
            values[.provider] = insurer(in: lines)
        case .vehicleRegistration:
            values[.vin] = firstMatch(#"\b([A-HJ-NPR-Z0-9]{17})\b"#, in: upper)
            values[.plate] = firstMatch(#"\b(?:PLATE|LICENSE PLATE|LIC PLATE|TAG)[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9-]{2,8})\b"#, in: upper)
            values[.state] = usState(in: lines)
        case .socialSecurityCard:
            values[.documentNumber] = firstMatch(#"\b(\d{3}[- ]\d{2}[- ]\d{4})\b"#, in: upper)
        case .greenCard, .residencePermit, .visa:
            values[.documentNumber] = firstMatch(#"\b(?:USCIS|CARD|DOCUMENT|PERMIT|VISA)[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9-]{6,15})"#, in: upper)
                ?? firstMatch(#"\b(\d{3}-\d{3}-\d{3})\b"#, in: upper)
            values[.visaType] = firstMatch(#"\b(?:CATEGORY|TYPE|CLASS)[ \t]*[:.]?[ \t]*([A-Z0-9]{1,4})\b"#, in: upper)
        case .membershipCard:
            values[.memberID] = firstMatch(#"\b(?:MEMBER(?:SHIP)?|CARD|ACCOUNT)[ \t]*(?:ID|NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9][A-Z0-9 -]{4,20}[A-Z0-9])"#, in: upper)
            values[.provider] = lines.first.map(titleCase)
        case .warranty:
            values[.serialNumber] = firstMatch(#"\b(?:SERIAL|S/N|SN)[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9-]{5,20})"#, in: upper)
            values[.price] = firstMatch(#"(?:TOTAL|AMOUNT)[ \t]*[:.]?[ \t]*(\$?\s?\d{1,6}[.,]\d{2})"#, in: upper)
            values[.purchaseDate] = values[.issueDate] ?? allDates.first
            values[.issueDate] = nil
            values[.store] = lines.first.map(titleCase)
        case .vaccinationRecord:
            values[.lotNumber] = firstMatch(#"\bLOT[ \t]*(?:NO\.?|NUMBER|#)?[ \t]*[:#.]?[ \t]*([A-Z0-9-]{3,12})"#, in: upper)
        default:
            break
        }

        // Names.
        if let name = labeledValue(["NAME", "MEMBER NAME", "MEMBER", "SUBSCRIBER", "INSURED", "POLICYHOLDER", "NAMED INSURED"], lines) {
            values[.fullName] = titleCase(name)
        } else if kind == .driversLicense || kind == .stateID, let name = licenseName(lines) {
            values[.fullName] = name
        }

        values = values.mapValues { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.value.isEmpty }
        return ExtractedDocument(kind: kind, title: nil, values: values, source: .text, confidence: confidence)
    }

    // MARK: MRZ

    static func fromMRZ(_ mrz: MRZResult, text: String) -> ExtractedDocument {
        var values: [FieldKey: String] = [:]
        values[.fullName] = mrz.fullName
        values[.documentNumber] = mrz.documentNumber
        values[.nationality] = mrz.nationality
        values[.issuingCountry] = mrz.issuingState
        values[.dateOfBirth] = mrz.dateOfBirth.map(format)
        values[.expiryDate] = mrz.expiryDate.map(format)
        let kind: DocumentKind
        if mrz.isPassport {
            kind = .passport
        } else if mrz.isVisa {
            kind = .visa
        } else if text.uppercased().contains("PERMANENT RESIDENT") || mrz.documentCode == "C1" {
            kind = .greenCard
        } else if text.uppercased().contains("RESIDENCE") || text.uppercased().contains("PERMIT") {
            kind = .residencePermit
        } else {
            kind = .stateID
        }
        // Dates printed in the visual zone (issue date) aren't in the MRZ.
        let lines = text.uppercased().components(separatedBy: .newlines)
        for (key, date) in labeledDates(lines) where key == .issueDate {
            values[key] = date
        }
        if kind == .passport, let place = labeledValue(["PLACE OF ISSUE", "AUTHORITY", "ISSUING AUTHORITY"], lines) {
            values[.placeOfIssue] = titleCase(place)
        }
        return ExtractedDocument(kind: kind, title: nil, values: values, source: .mrz, confidence: mrz.isValid ? 0.99 : 0.85)
    }

    // MARK: Classification

    private static let signals: [(DocumentKind, [String], Double)] = [
        (.passport, ["PASSPORT", "PASSEPORT", "PASAPORTE", "P<"], 3),
        (.driversLicense, ["DRIVER LICENSE", "DRIVER'S LICENSE", "DRIVERS LICENSE", "DRIVER LICENCE", "DRIVING LICENCE", "DL ", "CLASS ", "ENDORSEMENTS", "OPERATOR"], 2),
        (.stateID, ["IDENTIFICATION CARD", "ID CARD", "STATE ID", "NOT FOR FEDERAL", "IDENTIFICATION ONLY"], 2),
        (.healthInsurance, ["HEALTH", "MEDICAL", "RX BIN", "RXBIN", "RXGRP", "RX GRP", "PCP", "COPAY", "PPO", "HMO", "EPO", "BLUE CROSS", "BLUE SHIELD", "AETNA", "CIGNA", "UNITEDHEALTHCARE", "KAISER", "HUMANA", "ANTHEM", "MEDICARE", "MEDICAID"], 1.5),
        (.dentalInsurance, ["DENTAL", "DELTA DENTAL", "METLIFE DENTAL", "GUARDIAN DENTAL"], 2.5),
        (.visionInsurance, ["VISION", "VSP", "EYEMED", "DAVIS VISION"], 2.5),
        (.autoInsurance, ["AUTO INSURANCE", "AUTOMOBILE", "PROOF OF INSURANCE", "INSURANCE IDENTIFICATION CARD", "GEICO", "PROGRESSIVE", "STATE FARM", "ALLSTATE", "LIBERTY MUTUAL", "VEHICLE", "VIN"], 1.5),
        (.homeInsurance, ["HOMEOWNERS", "RENTERS", "DWELLING", "PROPERTY INSURANCE", "HO-3", "HO-4"], 2.5),
        (.vehicleRegistration, ["REGISTRATION", "REGISTRATION CARD", "VEHICLE REGISTRATION", "PLATE", "VIN", "MAKE", "MODEL", "MOTOR VEHICLE"], 1.2),
        (.birthCertificate, ["CERTIFICATE OF BIRTH", "BIRTH CERTIFICATE", "CERTIFICATE OF LIVE BIRTH", "PLACE OF BIRTH", "VITAL RECORDS"], 2.5),
        (.socialSecurityCard, ["SOCIAL SECURITY", "SOCIAL SECURITY ADMINISTRATION"], 4),
        (.marriageCertificate, ["MARRIAGE", "CERTIFICATE OF MARRIAGE", "MARRIAGE LICENSE"], 3),
        (.visa, ["VISA", "ENTRIES", "ANNOTATION"], 2),
        (.residencePermit, ["RESIDENCE PERMIT", "RESIDENT PERMIT", "AUFENTHALTSTITEL", "TITRE DE SEJOUR"], 3),
        (.greenCard, ["PERMANENT RESIDENT", "RESIDENT SINCE", "USCIS", "UNITED STATES OF AMERICA PERMANENT"], 3),
        (.vaccinationRecord, ["VACCINATION", "VACCINE", "IMMUNIZATION", "COVID-19", "DOSE", "LOT"], 2),
        (.membershipCard, ["MEMBER SINCE", "MEMBERSHIP", "REWARDS", "LOYALTY", "COSTCO", "AAA", "LIBRARY"], 1.5),
        (.warranty, ["RECEIPT", "WARRANTY", "SUBTOTAL", "TOTAL", "SERIAL", "PURCHASE", "THANK YOU FOR SHOPPING"], 1.5),
    ]

    static func classify(_ upperText: String) -> (DocumentKind, Double) {
        var scores: [DocumentKind: Double] = [:]
        for (kind, words, weight) in signals {
            for word in words where upperText.contains(word) {
                scores[kind, default: 0] += weight
            }
        }
        // "INSURANCE" plus a member ID is almost always a health card.
        if upperText.contains("INSURANCE") || upperText.contains("MEMBER ID") {
            scores[.healthInsurance, default: 0] += upperText.contains("MEMBER") ? 1.5 : 0.5
        }
        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 1.5 else {
            return (.custom, 0)
        }
        let total = scores.values.reduce(0, +)
        return (best.key, min(0.95, best.value / max(total, 1) * min(1, best.value / 4)))
    }

    // MARK: Dates

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private static let labels: [(FieldKey, [String])] = [
        (.expiryDate, ["EXPIRES", "EXPIRATION", "EXPIRY", "EXP", "VALID UNTIL", "VALID THRU", "VALID THROUGH", "DATE OF EXPIRY", "DATE D'EXPIRATION", "4B"]),
        (.issueDate, ["ISSUED", "ISSUE DATE", "DATE OF ISSUE", "ISS", "4A", "DATE GIVEN", "DATE OF MARRIAGE"]),
        (.dateOfBirth, ["DATE OF BIRTH", "BIRTH DATE", "DOB", "BORN", "3 DOB"]),
        (.renewalDate, ["RENEWAL", "RENEWS", "EFFECTIVE THROUGH", "POLICY PERIOD", "TERM"]),
        (.purchaseDate, ["PURCHASE DATE", "DATE OF PURCHASE"]),
    ]

    private static func labeledDates(_ lines: [String]) -> [(FieldKey, String)] {
        var results: [(FieldKey, String)] = []
        for (index, line) in lines.enumerated() {
            for (key, words) in labels {
                guard words.contains(where: { containsWord($0, in: line) }) else { continue }
                // A date on the same line, after the label, or on the next line.
                if let date = dates(in: line).last ?? (index + 1 < lines.count ? dates(in: lines[index + 1]).first : nil) {
                    results.append((key, date))
                }
            }
        }
        return results
    }

    /// Every date in `line`, as "yyyy-MM-dd". US month-first order is assumed
    /// for numeric dates unless the first number can't be a month.
    static func dates(in line: String) -> [String] {
        var found: [String] = []
        let numeric = #"\b(\d{1,4})[/.\-](\d{1,2})[/.\-](\d{2,4})\b"#
        for match in matches(numeric, in: line) where match.count == 3 {
            let a = Int(match[0]) ?? 0, b = Int(match[1]) ?? 0, c = Int(match[2]) ?? 0
            if match[0].count == 4 {
                found.append(contentsOf: [make(a, b, c)].compactMap { $0 })
            } else {
                let year = c < 100 ? (c > 50 ? 1900 + c : 2000 + c) : c
                if a > 12 {
                    found.append(contentsOf: [make(year, b, a)].compactMap { $0 })
                } else {
                    found.append(contentsOf: [make(year, a, b)].compactMap { $0 })
                }
            }
        }
        let monthNames = months.joined(separator: "|")
        for match in matches(#"\b(\d{1,2})\s*("# + monthNames + #")[A-Z]*[\s/.,-]*(\d{2,4})\b"#, in: line) where match.count == 3 {
            let day = Int(match[0]) ?? 0
            let month = (months.firstIndex(of: match[1]) ?? -1) + 1
            var year = Int(match[2]) ?? 0
            if year < 100 { year += year > 50 ? 1900 : 2000 }
            if let date = make(year, month, day) { found.append(date) }
        }
        for match in matches(#"\b("# + monthNames + #")[A-Z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b"#, in: line) where match.count == 3 {
            let month = (months.firstIndex(of: match[0]) ?? -1) + 1
            if let date = make(Int(match[2]) ?? 0, month, Int(match[1]) ?? 0) { found.append(date) }
        }
        return found
    }

    private static func make(_ year: Int, _ month: Int, _ day: Int) -> String? {
        guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func format(_ components: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 1, components.day ?? 1)
    }

    // MARK: Text helpers

    private static func containsWord(_ word: String, in line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(^|[^A-Z0-9])" + NSRegularExpression.escapedPattern(for: word) + "($|[^A-Z0-9])") else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first?.first
    }

    /// Capture groups of every match.
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (1..<max(result.numberOfRanges, 1)).compactMap { index in
                Range(result.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }

    private static func labeledValue(_ labels: [String], _ lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            for label in labels {
                guard line.hasPrefix(label) else { continue }
                let rest = line.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: " :.-#"))
                let candidate = rest.isEmpty && index + 1 < lines.count ? lines[index + 1] : rest
                if isNameLike(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func isNameLike(_ string: String) -> Bool {
        let letters = string.filter(\.isLetter).count
        return letters >= 3 && Double(letters) / Double(max(string.count, 1)) > 0.7 && string.count < 48
    }

    /// AAMVA licenses print "1 SURNAME" and "2 GIVEN NAMES".
    private static func licenseName(_ lines: [String]) -> String? {
        let surname = lines.first { $0.hasPrefix("1 ") || $0.hasPrefix("LN ") }?.dropFirst(2).trimmingCharacters(in: .whitespaces)
        let given = lines.first { $0.hasPrefix("2 ") || $0.hasPrefix("FN ") }?.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard let surname, isNameLike(surname) else { return nil }
        return titleCase([given, surname].compactMap { $0 }.joined(separator: " "))
    }

    private static func phone(in text: String) -> String? {
        firstMatch(#"((?:1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4})"#, in: text)
    }

    private static let insurers = [
        "BLUE CROSS BLUE SHIELD", "BLUE CROSS", "BLUE SHIELD", "AETNA", "CIGNA", "UNITEDHEALTHCARE", "UNITED HEALTHCARE",
        "KAISER PERMANENTE", "HUMANA", "ANTHEM", "DELTA DENTAL", "METLIFE", "GUARDIAN", "VSP", "EYEMED", "GEICO",
        "PROGRESSIVE", "STATE FARM", "ALLSTATE", "LIBERTY MUTUAL", "NATIONWIDE", "FARMERS", "USAA", "TRAVELERS", "LEMONADE",
    ]

    private static func insurer(in lines: [String]) -> String? {
        for line in lines {
            if let name = insurers.first(where: { line.contains($0) }) { return titleCase(name) }
        }
        return lines.first(where: isNameLike).map(titleCase)
    }

    private static let states = [
        "ALABAMA", "ALASKA", "ARIZONA", "ARKANSAS", "CALIFORNIA", "COLORADO", "CONNECTICUT", "DELAWARE", "FLORIDA", "GEORGIA",
        "HAWAII", "IDAHO", "ILLINOIS", "INDIANA", "IOWA", "KANSAS", "KENTUCKY", "LOUISIANA", "MAINE", "MARYLAND",
        "MASSACHUSETTS", "MICHIGAN", "MINNESOTA", "MISSISSIPPI", "MISSOURI", "MONTANA", "NEBRASKA", "NEVADA", "NEW HAMPSHIRE",
        "NEW JERSEY", "NEW MEXICO", "NEW YORK", "NORTH CAROLINA", "NORTH DAKOTA", "OHIO", "OKLAHOMA", "OREGON", "PENNSYLVANIA",
        "RHODE ISLAND", "SOUTH CAROLINA", "SOUTH DAKOTA", "TENNESSEE", "TEXAS", "UTAH", "VERMONT", "VIRGINIA", "WASHINGTON",
        "WEST VIRGINIA", "WISCONSIN", "WYOMING", "DISTRICT OF COLUMBIA",
    ]

    private static func usState(in lines: [String]) -> String? {
        // States usually appear in the header; prefer longer names ("WEST VIRGINIA" over "VIRGINIA").
        for line in lines.prefix(6) {
            if let state = states.sorted(by: { $0.count > $1.count }).first(where: { line.contains($0) }) {
                return titleCase(state)
            }
        }
        return nil
    }

    static func titleCase(_ string: String) -> String {
        string.lowercased().split(separator: " ").map { word in
            word.count <= 2 && word.allSatisfy(\.isLetter) && word != "of" ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
