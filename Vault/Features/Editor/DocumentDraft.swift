import SwiftData
import SwiftUI

/// An editable copy of a document. Nothing touches the store until Save.
struct DocumentDraft {
    struct NewPage: Identifiable {
        let id = UUID()
        var source: PageSource
        var role: PageRole
        var preview: UIImage?
    }

    var title: String
    var kind: DocumentKind
    var color: CardColor
    var personID: UUID?
    var categoryID: UUID?
    var fields: [DocumentField]
    var notes: String
    var tags: [String]
    var recognizedText: String
    var isFavorite: Bool
    var remindersEnabled: Bool
    /// `nil` means "use the defaults for this kind".
    var customReminders: [ReminderOffset]?
    var renewalURL: String
    var newPages: [NewPage] = []
    var removedPageIDs: Set<UUID> = []
    var pageRoles: [UUID: PageRole] = [:]
    /// Where the pre-filled values came from, shown as a banner while reviewing.
    var extractionSource: ExtractedDocument.Source?
    var titleWasEdited = false

    /// A blank document of `kind`.
    init(kind: DocumentKind, personID: UUID? = nil, categoryID: UUID? = nil) {
        title = kind == .custom ? "" : kind.name
        self.kind = kind
        color = kind.defaultColor
        self.personID = personID
        self.categoryID = categoryID
        fields = kind.fieldTemplates.map { $0.makeField() }
        notes = ""
        tags = []
        recognizedText = ""
        isFavorite = false
        remindersEnabled = true
        customReminders = nil
        renewalURL = kind.defaultRenewalURL?.absoluteString ?? ""
    }

    /// A draft of an existing document.
    init(document: VaultDocument) {
        let payload = document.payload
        title = document.title
        kind = document.kind
        color = document.color
        personID = document.person?.id
        categoryID = document.category?.id
        fields = payload.fields
        notes = payload.notes
        tags = document.tags
        recognizedText = payload.recognizedText
        isFavorite = document.isFavorite
        remindersEnabled = document.remindersEnabled
        customReminders = document.usesDefaultReminders ? nil : document.reminderOffsets
        renewalURL = document.renewalURLString ?? ""
        titleWasEdited = true
    }

    /// A draft pre-filled from a scan.
    init(analysis: ScanAnalysis, pages: [PageSource], personID: UUID?) {
        self.init(kind: analysis.extracted.kind, personID: personID)
        apply(analysis.extracted)
        recognizedText = analysis.recognizedText
        extractionSource = analysis.extracted.source
        newPages = pages.enumerated().map { index, source in
            NewPage(source: source, role: index == 0 ? .front : (index == 1 && kind.isCardSized ? .back : .extra), preview: source.previewImage)
        }
    }

    mutating func apply(_ extracted: ExtractedDocument) {
        for (key, value) in extracted.values {
            if let index = fields.firstIndex(where: { $0.key == key }) {
                if fields[index].isEmpty { fields[index].value = value }
            } else if key != .custom {
                // A value the template doesn't have a slot for; keep it as an extra field.
                let isDate = DocumentField.parseDay(value) != nil && value.count == 10
                fields.append(DocumentField(key: key, label: Self.label(for: key), value: value, kind: isDate ? .date : .text))
            }
        }
        if let title = extracted.title, !titleWasEdited {
            self.title = title
        } else if !titleWasEdited, let provider = extracted.values[.provider], kind != .membershipCard {
            self.title = "\(provider) \(kind.name)"
        } else if !titleWasEdited, kind == .membershipCard, let provider = extracted.values[.provider] {
            self.title = provider
        }
    }

    /// Switches template, keeping every value already entered.
    mutating func changeKind(to newKind: DocumentKind) {
        let oldKind = kind
        kind = newKind
        var newFields = newKind.fieldTemplates.map { $0.makeField() }
        for field in fields where !field.isEmpty {
            if let index = newFields.firstIndex(where: { $0.key == field.key && $0.key != .custom }) {
                newFields[index].value = field.value
            } else {
                newFields.append(field)
            }
        }
        fields = newFields
        if color == oldKind.defaultColor { color = newKind.defaultColor }
        if !titleWasEdited || title == oldKind.name || title.isEmpty { title = newKind.name }
        if renewalURL.isEmpty || renewalURL == oldKind.defaultRenewalURL?.absoluteString {
            renewalURL = newKind.defaultRenewalURL?.absoluteString ?? ""
        }
    }

    var expiryDate: Date? {
        (fields.first { $0.key == .expiryDate && !$0.isEmpty } ?? fields.first { $0.key == .renewalDate && !$0.isEmpty })?.dateValue
    }

    var effectiveReminders: [ReminderOffset] {
        customReminders ?? ReminderDefaults.offsets(for: kind)
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func label(for key: FieldKey) -> String {
        for kind in DocumentKind.allCases {
            if let template = kind.fieldTemplates.first(where: { $0.key == key }) { return template.label }
        }
        return String(localized: "Field")
    }

    // MARK: Saving

    /// Writes the draft into `document` (creating it if `nil`), encrypting new
    /// pages off the main thread.
    @MainActor
    func save(into existing: VaultDocument?, store: VaultStore, context: ModelContext) async throws -> VaultDocument {
        let prepared = try await withThrowingTaskGroup(of: (Int, PreparedPage).self) { group in
            for (index, page) in newPages.enumerated() {
                let source = page.source
                group.addTask { (index, try await PagePreparer.prepare(source)) }
            }
            var results: [(Int, PreparedPage)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let document: VaultDocument
        if let existing {
            document = existing
        } else {
            document = VaultDocument(title: title, kind: kind)
            context.insert(document)
        }
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.kind = kind
        document.color = color
        document.isFavorite = isFavorite
        document.tags = tags
        document.remindersEnabled = remindersEnabled
        if let customReminders {
            document.reminderOffsets = customReminders
        } else {
            document.reminderOffsetsData = nil
        }
        let trimmedURL = renewalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        document.renewalURLString = trimmedURL.isEmpty ? nil : (trimmedURL.contains("://") ? trimmedURL : "https://" + trimmedURL)

        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        document.person = people.first { $0.id == personID }
        let categories = (try? context.fetch(FetchDescriptor<DocumentCategory>())) ?? []
        document.category = categories.first { $0.id == categoryID } ?? store.category(for: kind.category)

        let cleanedFields = fields.filter { !$0.isEmpty || $0.key != .custom || !$0.label.isEmpty }
        let hadExpiryField = cleanedFields.contains { $0.key == .expiryDate || $0.key == .renewalDate }
        document.payload = DocumentPayload(fields: cleanedFields, notes: notes, recognizedText: recognizedText)
        if !hadExpiryField { document.expiresOn = nil }

        // Pages: removals, role changes, then additions.
        for page in document.pages ?? [] {
            if removedPageIDs.contains(page.id) {
                context.delete(page)
            } else if let role = pageRoles[page.id] {
                page.role = role
            }
        }
        document.pages = (document.pages ?? []).filter { !removedPageIDs.contains($0.id) }
        var existingCount = document.pages?.count ?? 0
        for (page, preparedPage) in zip(newPages, prepared) {
            let replaced = page.role == .extra ? nil : document.pages?.first { $0.role == page.role }
            if let replaced {
                replaced.role = .extra
            }
            let newPage = DocumentPage(prepared: preparedPage, role: page.role, index: existingCount)
            existingCount += 1
            context.insert(newPage)
            newPage.document = document
            document.pages = (document.pages ?? []) + [newPage]
        }
        document.updatedAt = .now
        store.vaultDidChange()
        return document
    }
}
