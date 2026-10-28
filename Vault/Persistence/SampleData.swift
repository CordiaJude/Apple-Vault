#if DEBUG
import SwiftData
import SwiftUI

/// Obviously fake sample documents so the design is visible on first launch.
/// Debug builds only; never compiled into Release.
@MainActor
enum SampleData {
    static func seedIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.didSeedSampleData) else { return }
        let count = (try? context.fetchCount(FetchDescriptor<VaultDocument>())) ?? 0
        guard count == 0 else { return }
        seed(in: context)
        UserDefaults.standard.set(true, forKey: SettingsKey.didSeedSampleData)
    }

    static func reset(in context: ModelContext) {
        try? context.delete(model: DocumentPage.self)
        try? context.delete(model: VaultDocument.self)
        try? context.delete(model: Person.self)
        try? context.save()
        seed(in: context)
    }

    private static func seed(in context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<DocumentCategory>())) ?? []
        func category(_ kind: DocumentKind) -> DocumentCategory? {
            categories.first { $0.builtInRaw == kind.category.rawValue }
        }

        let me = Person(name: "Jordan Appleseed", relationship: .me, color: .blue, emoji: "🧑‍💻", sortOrder: 0)
        let partner = Person(name: "Taylor Appleseed", relationship: .partner, color: .purple, emoji: "👩", sortOrder: 1)
        let child = Person(name: "Riley Appleseed", relationship: .child, color: .orange, emoji: "👧", sortOrder: 2)
        [me, partner, child].forEach(context.insert)

        let calendar = Calendar.current
        func day(_ component: Calendar.Component, _ value: Int) -> String {
            DocumentField.formatDay(calendar.date(byAdding: component, value: value, to: .now)!)
        }

        func add(_ kind: DocumentKind, _ title: String, person: Person, values: [FieldKey: String], notes: String = "",
                 favorite: Bool = false, tags: [String] = [], front: AnyView? = nil, back: AnyView? = nil) {
            let document = VaultDocument(title: title, kind: kind)
            context.insert(document)
            document.person = person
            document.category = category(kind)
            document.isFavorite = favorite
            document.tags = tags
            var fields = kind.fieldTemplates.map { $0.makeField() }
            for index in fields.indices { fields[index].value = values[fields[index].key] ?? "" }
            document.payload = DocumentPayload(fields: fields, notes: notes, recognizedText: values.values.joined(separator: "\n"))
            for (role, view) in [(PageRole.front, front), (.back, back)] {
                guard let view, let page = makePage(view, role: role) else { continue }
                context.insert(page)
                page.document = document
            }
        }

        add(.passport, "Passport", person: me, values: [
            .fullName: "Jordan Appleseed", .documentNumber: "X00000001", .nationality: "Sampleland",
            .dateOfBirth: "1988-04-12", .issueDate: day(.year, -10), .expiryDate: day(.month, 5), .placeOfIssue: "Specimen City",
        ], notes: "Sample document. Not a real passport.", tags: ["travel"],
            front: AnyView(SamplePassport(expiry: day(.month, 5))))

        add(.driversLicense, "Driver’s License", person: me, values: [
            .fullName: "Jordan Appleseed", .documentNumber: "D000-1234-5678", .state: "Example State", .licenseClass: "C",
            .dateOfBirth: "1988-04-12", .issueDate: day(.year, -2), .expiryDate: day(.year, 3), .restrictions: "None",
        ], favorite: true, front: AnyView(SampleLicense(expiry: day(.year, 3))), back: AnyView(SampleCardBack(title: "EXAMPLE STATE", color: .blue)))

        add(.healthInsurance, "Example Health Plan", person: me, values: [
            .provider: "Example Health Plan", .fullName: "Jordan Appleseed", .memberID: "XEH000123456",
            .groupNumber: "000999", .policyNumber: "PPO-SAMPLE", .phone: "1-555-010-0199", .renewalDate: day(.day, 20),
        ], favorite: true, front: AnyView(SampleInsurance()), back: AnyView(SampleCardBack(title: "EXAMPLE HEALTH PLAN", color: .teal)))

        add(.autoInsurance, "Auto Insurance", person: me, values: [
            .provider: "Sample Mutual", .fullName: "Jordan Appleseed", .policyNumber: "AUTO-0000-0000", .phone: "1-555-010-0142",
            .renewalDate: day(.day, -9),
        ])

        add(.vehicleRegistration, "Vehicle Registration", person: me, values: [
            .plate: "SAMPLE1", .vin: "1SAMPLE0000000001", .vehicle: "2021 Example Hatchback", .state: "Example State", .expiryDate: day(.month, 2),
        ])

        add(.passport, "Passport", person: partner, values: [
            .fullName: "Taylor Appleseed", .documentNumber: "X00000002", .nationality: "Sampleland",
            .dateOfBirth: "1990-09-30", .issueDate: day(.year, -6), .expiryDate: day(.year, 4),
        ])

        add(.dentalInsurance, "Sample Dental", person: partner, values: [
            .provider: "Sample Dental", .fullName: "Taylor Appleseed", .memberID: "SD-000-777", .groupNumber: "4400", .renewalDate: day(.month, 8),
        ])

        add(.birthCertificate, "Birth Certificate", person: child, values: [
            .fullName: "Riley Appleseed", .dateOfBirth: "2018-06-01", .placeOfBirth: "Specimen City", .documentNumber: "BC-0000-0001",
            .issuer: "Example Vital Records Office",
        ])

        add(.vaccinationRecord, "Vaccination Record", person: child, values: [
            .fullName: "Riley Appleseed", .vaccine: "Sample Booster", .issueDate: day(.month, -11), .provider: "Example Pediatrics",
            .expiryDate: day(.month, 1),
        ])

        add(.membershipCard, "Sample Wholesale Club", person: partner, values: [
            .provider: "Sample Wholesale Club", .fullName: "Taylor Appleseed", .memberID: "0000 1111 2222", .expiryDate: day(.month, 10),
        ])

        try? context.save()
    }

    private static func makePage(_ view: AnyView, role: PageRole) -> DocumentPage? {
        let renderer = ImageRenderer(content: view.frame(width: 428, height: 270).environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let image = renderer.uiImage,
              let jpeg = image.jpegData(compressionQuality: 0.9),
              let data = try? VaultCrypto.seal(jpeg),
              let thumb = image.vaultScaled(maxDimension: PagePreparer.thumbnailDimension).jpegData(compressionQuality: 0.8)
        else { return nil }
        let page = DocumentPage(role: role, index: role == .front ? 0 : 1)
        page.encryptedData = data
        page.encryptedThumbnail = try? VaultCrypto.seal(thumb)
        page.pixelWidth = image.size.width * image.scale
        page.pixelHeight = image.size.height * image.scale
        return page
    }
}

// MARK: - Fake document artwork (clearly marked SPECIMEN)

private struct Specimen: View {
    var body: some View {
        Text("SPECIMEN")
            .font(.system(size: 54, weight: .black))
            .foregroundStyle(.red.opacity(0.18))
            .rotationEffect(.degrees(-18))
    }
}

private struct SamplePassport: View {
    let expiry: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.92, blue: 0.86), Color(red: 0.85, green: 0.88, blue: 0.84)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PASSPORT · SAMPLELAND").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("Type P").font(.system(size: 10))
                }
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.35))
                        .frame(width: 84, height: 104)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 54)).foregroundStyle(.gray.opacity(0.7)))
                    VStack(alignment: .leading, spacing: 3) {
                        row("Surname", "APPLESEED")
                        row("Given names", "JORDAN")
                        row("Passport No.", "X00000001")
                        row("Date of birth", "12 APR 1988")
                        row("Date of expiry", expiry)
                    }
                }
                Spacer(minLength: 0)
                Text("P<SPLAPPLESEED<<JORDAN<<<<<<<<<<<<<<<<<<<<<<\nX000000018SPL8804124M3001019<<<<<<<<<<<<<<04")
                    .font(.system(size: 9.5, design: .monospaced))
            }
            .foregroundStyle(.black.opacity(0.8))
            .padding(14)
            Specimen()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 8)).foregroundStyle(.gray)
            Text(value).font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct SampleLicense: View {
    let expiry: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.86, green: 0.92, blue: 0.99), Color(red: 0.98, green: 0.97, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("EXAMPLE STATE").font(.system(size: 18, weight: .heavy)).foregroundStyle(.blue)
                    Spacer()
                    Text("DRIVER LICENSE").font(.system(size: 12, weight: .bold))
                }
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.15))
                        .frame(width: 90, height: 112)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 58)).foregroundStyle(.blue.opacity(0.4)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DL D000-1234-5678").font(.system(size: 13, weight: .bold))
                        Text("EXP \(expiry)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                        Text("1 APPLESEED\n2 JORDAN").font(.system(size: 12, weight: .semibold))
                        Text("DOB 04/12/1988   CLASS C").font(.system(size: 11))
                        Text("RSTR NONE").font(.system(size: 11))
                    }
                }
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(14)
            Specimen()
        }
    }
}

private struct SampleInsurance: View {
    var body: some View {
        ZStack {
            Color.white
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cross.case.fill").foregroundStyle(.teal)
                    Text("Example Health Plan").font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text("PPO").font(.system(size: 14, weight: .heavy)).foregroundStyle(.teal)
                }
                Text("Member: JORDAN APPLESEED").font(.system(size: 12, weight: .semibold))
                Text("Member ID: XEH000123456").font(.system(size: 13, design: .monospaced))
                Text("Group: 000999").font(.system(size: 12, design: .monospaced))
                HStack {
                    Text("PCP $20").font(.system(size: 11))
                    Text("Specialist $40").font(.system(size: 11))
                    Text("ER $250").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Member Services 1-555-010-0199").font(.system(size: 10))
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(16)
            Specimen()
        }
    }
}

private struct SampleCardBack: View {
    let title: String
    let color: Color

    var body: some View {
        ZStack {
            Color(white: 0.96)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(.black.opacity(0.85)).frame(height: 34).padding(.horizontal, -16)
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
                Text("This card is a sample created by Vault for demonstration. It is not a real document and has no value.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(0..<46, id: \.self) { index in
                        Rectangle().fill(.black).frame(width: index % 3 == 0 ? 3 : 1.5, height: 36)
                    }
                }
            }
            .padding(16)
            Specimen()
        }
    }
}
#endif
