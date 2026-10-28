import Foundation

/// Reads the Machine Readable Zone printed on passports (TD3), ID cards and
/// residence permits (TD1, TD2) and visas (MRV-A/B), per ICAO Doc 9303.
///
/// Check digits are verified, and common OCR confusions (O/0, I/1, «/<) are
/// repaired using them, so a passport scan fills fields exactly.
nonisolated struct MRZResult: Equatable, Sendable {
    enum Format: String, Sendable {
        case td1, td2, td3, mrvA, mrvB
    }

    var format: Format
    var documentCode: String
    var issuingState: String
    var surname: String
    var givenNames: String
    var documentNumber: String
    var nationality: String
    var dateOfBirth: DateComponents?
    var sex: String
    var expiryDate: DateComponents?
    var optionalData: String
    /// True when every check digit matched.
    var isValid: Bool

    var fullName: String {
        [givenNames, surname].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isPassport: Bool { documentCode.hasPrefix("P") }
    var isVisa: Bool { documentCode.hasPrefix("V") }
}

nonisolated enum MRZParser {
    /// Finds and parses an MRZ anywhere in recognized text.
    static func parse(text: String) -> MRZResult? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(normalize)
            .filter { $0.count >= 28 && $0.contains("<") }
        guard !lines.isEmpty else { return nil }

        // Try the most specific layouts first, over consecutive lines.
        for index in lines.indices {
            if index + 2 < lines.count, let result = parseTD1(lines[index], lines[index + 1], lines[index + 2]) {
                return result
            }
            if index + 1 < lines.count {
                if let result = parseTD3(lines[index], lines[index + 1]) { return result }
                if let result = parseTD2(lines[index], lines[index + 1]) { return result }
            }
        }
        return nil
    }

    // MARK: Formats

    static func parseTD3(_ first: String, _ second: String) -> MRZResult? {
        guard first.count >= 42, second.count >= 42, let code = first.first, code == "P" || code == "V" else { return nil }
        let l1 = pad(first, 44)
        let l2 = pad(second, 44)
        let documentCode = cleanCode(l1[0..<2])
        let isVisa = code == "V"

        let number = repairAlphanumeric(l2[0..<9], check: l2[9])
        let birth = repairNumeric(l2[13..<19], check: l2[19])
        let expiry = repairNumeric(l2[21..<27], check: l2[27])
        var checks = [number.valid, birth.valid, expiry.valid]
        if !isVisa {
            let personal = l2[28..<42]
            let personalValid = personal.allSatisfy { $0 == "<" } && (l2[42] == "<" || l2[42] == "0") || checkDigit(personal) == digit(l2[42])
            let composite = number.value + l2[9] + birth.value + l2[19] + expiry.value + l2[27] + personal + l2[42]
            checks.append(personalValid)
            checks.append(checkDigit(composite) == digit(l2[43]))
        }
        guard checks.filter({ $0 }).count >= 2 else { return nil }
        let (surname, given) = names(l1[5..<44])

        return MRZResult(
            format: isVisa ? .mrvA : .td3,
            documentCode: documentCode,
            issuingState: clean(l1[2..<5]),
            surname: surname,
            givenNames: given,
            documentNumber: clean(number.value),
            nationality: clean(l2[10..<13]),
            dateOfBirth: date(birth.value, isExpiry: false),
            sex: clean(l2[20..<21]),
            expiryDate: date(expiry.value, isExpiry: true),
            optionalData: clean(l2[28..<42]),
            isValid: !checks.contains(false)
        )
    }

    static func parseTD2(_ first: String, _ second: String) -> MRZResult? {
        guard (34...38).contains(first.count), (34...38).contains(second.count) else { return nil }
        let l1 = pad(first, 36)
        let l2 = pad(second, 36)
        guard let code = l1.first, "ACIV".contains(code) else { return nil }

        let number = repairAlphanumeric(l2[0..<9], check: l2[9])
        let birth = repairNumeric(l2[13..<19], check: l2[19])
        let expiry = repairNumeric(l2[21..<27], check: l2[27])
        let checks = [number.valid, birth.valid, expiry.valid]
        guard checks.filter({ $0 }).count >= 2 else { return nil }
        let (surname, given) = names(l1[5..<36])

        return MRZResult(
            format: code == "V" ? .mrvB : .td2,
            documentCode: cleanCode(l1[0..<2]),
            issuingState: clean(l1[2..<5]),
            surname: surname,
            givenNames: given,
            documentNumber: clean(number.value),
            nationality: clean(l2[10..<13]),
            dateOfBirth: date(birth.value, isExpiry: false),
            sex: clean(l2[20..<21]),
            expiryDate: date(expiry.value, isExpiry: true),
            optionalData: clean(l2[28..<35]),
            isValid: !checks.contains(false)
        )
    }

    static func parseTD1(_ first: String, _ second: String, _ third: String) -> MRZResult? {
        guard (28...32).contains(first.count), (28...32).contains(second.count), (28...32).contains(third.count) else { return nil }
        let l1 = pad(first, 30)
        let l2 = pad(second, 30)
        let l3 = pad(third, 30)
        guard let code = l1.first, "ACI".contains(code) else { return nil }

        let number = repairAlphanumeric(l1[5..<14], check: l1[14])
        let birth = repairNumeric(l2[0..<6], check: l2[6])
        let expiry = repairNumeric(l2[8..<14], check: l2[14])
        let checks = [number.valid, birth.valid, expiry.valid]
        guard checks.filter({ $0 }).count >= 2 else { return nil }
        let (surname, given) = names(l3[0..<30])

        return MRZResult(
            format: .td1,
            documentCode: cleanCode(l1[0..<2]),
            issuingState: clean(l1[2..<5]),
            surname: surname,
            givenNames: given,
            documentNumber: clean(number.value),
            nationality: clean(l2[15..<18]),
            dateOfBirth: date(birth.value, isExpiry: false),
            sex: clean(l2[7..<8]),
            expiryDate: date(expiry.value, isExpiry: true),
            optionalData: clean(l1[15..<30]),
            isValid: !checks.contains(false)
        )
    }

    // MARK: Check digits

    /// ICAO 9303 check digit: weights 7, 3, 1; digits as-is, A–Z as 10–35, '<' as 0.
    static func checkDigit(_ string: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in string.enumerated() {
            sum += value(of: character) * weights[index % 3]
        }
        return sum % 10
    }

    private static func value(of character: Character) -> Int {
        if let digit = character.wholeNumberValue { return digit }
        if let ascii = character.asciiValue, character.isUppercase, character.isLetter { return Int(ascii) - 55 }
        return 0
    }

    private static func digit(_ string: String) -> Int? {
        repairDigit(string).first?.wholeNumberValue
    }

    // MARK: OCR repair

    private static let toDigit: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "Z": "2", "S": "5", "B": "8", "G": "6", "T": "7"]

    private static func repairDigit(_ string: String) -> String {
        String(string.map { toDigit[$0] ?? $0 })
    }

    /// A numeric field (dates): map look-alike letters to digits.
    private static func repairNumeric(_ field: String, check: String) -> (value: String, valid: Bool) {
        let repaired = repairDigit(field)
        return (repaired, digit(check) == checkDigit(repaired))
    }

    /// An alphanumeric field (document numbers): try the raw text, then
    /// swap ambiguous characters until the check digit matches.
    private static func repairAlphanumeric(_ field: String, check: String) -> (value: String, valid: Bool) {
        guard let expected = digit(check) else { return (field, false) }
        if checkDigit(field) == expected { return (field, true) }
        let swaps: [Character: Character] = ["O": "0", "0": "O", "I": "1", "1": "I", "S": "5", "5": "S", "B": "8", "8": "B", "Z": "2", "2": "Z"]
        let characters = Array(field)
        for index in characters.indices {
            guard let replacement = swaps[characters[index]] else { continue }
            var candidate = characters
            candidate[index] = replacement
            let string = String(candidate)
            if checkDigit(string) == expected { return (string, true) }
        }
        return (field, false)
    }

    // MARK: Helpers

    static func normalize(_ line: String) -> String {
        var result = line.uppercased()
        for (from, to) in [("«", "<<"), ("‹", "<"), ("‘", "<"), (" ", ""), ("\t", "")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return String(result.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "<") })
    }

    private static func pad(_ line: String, _ length: Int) -> Line {
        Line(characters: Array(line.prefix(length)) + Array(repeating: Character("<"), count: max(0, length - line.count)))
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func cleanCode(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "")
    }

    private static func names(_ field: String) -> (surname: String, given: String) {
        let parts = field.components(separatedBy: "<<")
        let surname = parts.first.map(clean) ?? ""
        let given = parts.dropFirst().joined(separator: " ").replacingOccurrences(of: "<", with: " ")
            .split(separator: " ").joined(separator: " ")
        return (titleCase(surname), titleCase(given))
    }

    private static func titleCase(_ string: String) -> String {
        string.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func date(_ yymmdd: String, isExpiry: Bool) -> DateComponents? {
        guard yymmdd.count == 6, let yy = Int(yymmdd.prefix(2)), let mm = Int(yymmdd.dropFirst(2).prefix(2)), let dd = Int(yymmdd.suffix(2)),
              (1...12).contains(mm), (1...31).contains(dd)
        else { return nil }
        let currentYY = Calendar(identifier: .gregorian).component(.year, from: Date()) % 100
        let century: Int
        if isExpiry {
            century = yy >= 70 ? 1900 : 2000
        } else {
            century = yy > currentYY ? 1900 : 2000
        }
        return DateComponents(year: century + yy, month: mm, day: dd)
    }
}

/// One fixed-width MRZ line, addressed by character offsets.
private nonisolated struct Line {
    let characters: [Character]

    var first: Character? { characters.first }

    subscript(range: Range<Int>) -> String {
        String(characters[range.clamped(to: characters.indices)])
    }

    subscript(index: Int) -> String {
        characters.indices.contains(index) ? String(characters[index]) : "<"
    }
}
