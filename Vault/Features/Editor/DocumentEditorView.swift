import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Create, review or edit a document. After a scan this is the confirmation
/// step: every value Vault found is shown for the person to check before
/// anything is saved.
struct DocumentEditorView: View {
    enum Mode {
        case create(DocumentDraft)
        case edit(VaultDocument)
    }

    let mode: Mode
    var onSaved: ((VaultDocument) -> Void)?

    @Environment(VaultStore.self) private var store
    @Environment(HUDCenter.self) private var hud
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.createdAt)]) private var people: [Person]
    @Query(sort: \DocumentCategory.sortOrder) private var categories: [DocumentCategory]

    @State private var draft: DocumentDraft
    @State private var isSaving = false
    @State private var saveCount = 0
    @State private var errorMessage: String?
    @State private var isPickingKind = false
    @State private var isEditingReminders = false
    @State private var addingPagesFrom: AppRouter.AddSource?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var tagText = ""
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: UUID?

    init(mode: Mode, onSaved: ((VaultDocument) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create(let draft): _draft = State(initialValue: draft)
        case .edit(let document): _draft = State(initialValue: DocumentDraft(document: document))
        }
    }

    private var existing: VaultDocument? {
        if case .edit(let document) = mode { return document }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let source = draft.extractionSource {
                    Section {
                        ExtractionBanner(source: source, kind: draft.kind)
                    }
                }

                Section {
                    CardFace(
                        title: draft.title.isEmpty ? draft.kind.name : draft.title,
                        kind: draft.kind,
                        color: draft.color,
                        holder: people.first { $0.id == draft.personID }?.displayName,
                        expiresOn: draft.expiryDate,
                        isFavorite: draft.isFavorite
                    )
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .animation(.default, value: draft.color)
                    .accessibilityHidden(true)
                }

                Section {
                    TextField("Title", text: $draft.title)
                        .font(.headline)
                        .onChange(of: draft.title) { _, _ in draft.titleWasEdited = true }
                    Button {
                        isPickingKind = true
                    } label: {
                        LabeledContent("Type") {
                            Label(draft.kind.name, systemImage: draft.kind.symbol)
                                .foregroundStyle(.primary)
                        }
                    }
                    .foregroundStyle(.primary)
                    Picker("Belongs To", selection: $draft.personID) {
                        Text("No One").tag(UUID?.none)
                        ForEach(people) { person in
                            Text(person.displayName).tag(UUID?.some(person.id))
                        }
                    }
                    Picker("Category", selection: $draft.categoryID) {
                        Text("Automatic").tag(UUID?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(UUID?.some(category.id))
                        }
                    }
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $draft.color)
                }

                fieldsSection

                pagesSection

                expirationSection

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }

                tagsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "New Document" : "Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if existing == nil { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(role: .confirm) { save() }
                            .disabled(!draft.canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(existing == nil || isSaving)
            .confirmationDialog("Discard this document?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(isPresented: $isPickingKind) {
                TemplatePickerView(selection: draft.kind) { kind in
                    draft.changeKind(to: kind)
                }
            }
            .sheet(isPresented: $isEditingReminders) {
                ReminderOffsetsEditor(kind: draft.kind, offsets: $draft.customReminders)
            }
            .fullScreenCover(item: Binding(get: { addingPagesFrom == .scan ? addingPagesFrom : nil }, set: { addingPagesFrom = $0 })) { _ in
                DocumentScannerView { images in
                    addPages(images.map(PageSource.image))
                    addingPagesFrom = nil
                } onCancel: {
                    addingPagesFrom = nil
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: Binding(get: { addingPagesFrom == .photos }, set: { if !$0 { addingPagesFrom = nil } }),
                          selection: $photoItems, maxSelectionCount: 10, matching: .images)
            .fileImporter(isPresented: Binding(get: { addingPagesFrom == .files }, set: { if !$0 { addingPagesFrom = nil } }),
                          allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    addPages(ImportLoader.load(urls: urls))
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    addPages(await ImportLoader.load(items: items))
                    photoItems = []
                }
            }
            .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: saveCount)
        }
    }

    // MARK: Fields

    private var fieldsSection: some View {
        Section {
            ForEach($draft.fields) { $field in
                FieldEditorRow(field: $field, focus: $focusedField)
            }
            .onDelete { draft.fields.remove(atOffsets: $0) }
            .onMove { draft.fields.move(fromOffsets: $0, toOffset: $1) }

            Menu {
                ForEach(FieldKind.allCases, id: \.self) { kind in
                    Button {
                        let field = DocumentField(key: .custom, label: "", kind: kind)
                        draft.fields.append(field)
                        focusedField = field.id
                    } label: {
                        Label(kind.name, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label("Add Field", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Details")
        } footer: {
            if draft.extractionSource != nil {
                Text("Check each value against your document before saving.")
            }
        }
    }

    // MARK: Pages

    private var pagesSection: some View {
        Section {
            let existingPages = (existing?.sortedPages ?? []).filter { !draft.removedPageIDs.contains($0.id) }
            ForEach(existingPages) { page in
                PageEditorRow(
                    thumbnail: { PageThumbnail(page: page) },
                    title: page.isPDF ? String(localized: "PDF") : nil,
                    role: Binding(get: { draft.pageRoles[page.id] ?? page.role }, set: { draft.pageRoles[page.id] = $0 }),
                    onDelete: { draft.removedPageIDs.insert(page.id) }
                )
            }
            ForEach($draft.newPages) { $page in
                let isPDF: Bool = { if case .pdf = page.source { return true } else { return false } }()
                PageEditorRow(
                    thumbnail: {
                        Group {
                            if let preview = page.preview {
                                Image(uiImage: preview).resizable().scaledToFit()
                            } else {
                                Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    },
                    title: isPDF ? String(localized: "PDF") : nil,
                    role: $page.role,
                    onDelete: { draft.newPages.removeAll { $0.id == page.id } }
                )
            }
            Menu {
                Button { addingPagesFrom = .scan } label: { Label("Scan", systemImage: "doc.viewfinder") }
                    .disabled(!DocumentScannerView.isSupported)
                Button { addingPagesFrom = .photos } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                Button { addingPagesFrom = .files } label: { Label("Import from Files", systemImage: "folder") }
            } label: {
                Label("Add Pages", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Images & Pages")
        } footer: {
            Text("The front and back are shown on the card; other pages and PDFs are kept with the document.")
        }
    }

    // MARK: Expiration

    private var expirationSection: some View {
        Section {
            Toggle("Expiration Reminders", isOn: $draft.remindersEnabled)
            if draft.remindersEnabled {
                Button {
                    isEditingReminders = true
                } label: {
                    LabeledContent("Remind Me") {
                        Text(draft.effectiveReminders.map(\.description).formatted(.list(type: .and)))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .foregroundStyle(.primary)
            }
            TextField("Renewal Website", text: $draft.renewalURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Expiration & Renewal")
        } footer: {
            if draft.expiryDate == nil {
                Text("Add an expiration date above to get reminders.")
            } else if draft.kind == .passport {
                Text("Passports remind you early because many countries require six months of validity to enter.")
            }
        }
    }

    // MARK: Tags

    private var tagsSection: some View {
        Section("Tags") {
            if !draft.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(draft.tags, id: \.self) { tag in
                            Button {
                                draft.tags.removeAll { $0 == tag }
                            } label: {
                                Label(tag, systemImage: "xmark.circle.fill")
                                    .labelStyle(TagLabelStyle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                    }
                }
            }
            TextField("Add Tag", text: $tagText)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit {
                    let tag = tagText.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    if !tag.isEmpty, !draft.tags.contains(tag) { draft.tags.append(tag) }
                    tagText = ""
                }
        }
    }

    // MARK: Actions

    private func addPages(_ sources: [PageSource]) {
        let keptPages = (existing?.sortedPages ?? []).filter { !draft.removedPageIDs.contains($0.id) }
        var usedRoles = Set(keptPages.map { draft.pageRoles[$0.id] ?? $0.role })
        usedRoles.formUnion(draft.newPages.map(\.role))
        for source in sources {
            var role = PageRole.extra
            if !usedRoles.contains(.front) {
                role = .front
            } else if !usedRoles.contains(.back), draft.kind.isCardSized, case .image = source {
                role = .back
            }
            usedRoles.insert(role)
            draft.newPages.append(.init(source: source, role: role, preview: source.previewImage))
        }
    }

    private func save() {
        focusedField = nil
        isSaving = true
        Task {
            do {
                let document = try await draft.save(into: existing, store: store, context: modelContext)
                saveCount += 1
                hud.show(String(localized: "Saved"), symbol: "checkmark.circle.fill")
                onSaved?(document)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Rows

private struct FieldEditorRow: View {
    @Binding var field: DocumentField
    var focus: FocusState<UUID?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if field.key == .custom {
                TextField("Label", text: $field.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(field.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch field.kind {
            case .date:
                DateFieldEditor(field: $field)
            default:
                TextField(field.label.isEmpty ? String(localized: "Value") : field.label, text: $field.value)
                    .font(field.kind == .identifier ? .body.monospaced() : .body)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(field.kind == .identifier ? .characters : .words)
                    .autocorrectionDisabled(field.kind != .text)
                    .focused(focus, equals: field.id)
                    .privacySensitive(field.isSensitive)
            }
            if field.key == .custom {
                Toggle("Sensitive", isOn: $field.isSensitive)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    private var keyboard: UIKeyboardType {
        switch field.kind {
        case .phone: .phonePad
        case .url: .URL
        default: .default
        }
    }
}

private struct DateFieldEditor: View {
    @Binding var field: DocumentField

    var body: some View {
        if let date = field.dateValue {
            HStack {
                DatePicker(field.label, selection: Binding(get: { date }, set: { field.dateValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Button {
                    field.value = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(field.label)")
            }
        } else {
            Button("Add Date") {
                field.dateValue = field.key == .dateOfBirth
                    ? Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    : Calendar.current.date(byAdding: .year, value: field.key == .expiryDate || field.key == .renewalDate ? 1 : 0, to: .now)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct PageEditorRow<Thumbnail: View>: View {
    @ViewBuilder var thumbnail: () -> Thumbnail
    var title: String?
    @Binding var role: PageRole
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            thumbnail()
                .frame(width: 64, height: 44)
            if let title {
                Text(title)
            } else {
                Picker("Side", selection: $role) {
                    ForEach(PageRole.allCases, id: \.self) { role in
                        Text(role.name).tag(role)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Page")
        }
    }
}

private struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: .capsule)
    }
}

/// Shows where pre-filled values came from.
private struct ExtractionBanner: View {
    let source: ExtractedDocument.Source
    let kind: DocumentKind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .custom ? String(localized: "Review Your Document") : String(localized: "Looks Like a \(kind.name)"))
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch source {
        case .mrz: "text.viewfinder"
        case .intelligence: "apple.intelligence"
        case .text: "doc.text.magnifyingglass"
        }
    }

    private var detail: String {
        switch source {
        case .mrz: String(localized: "Read from the machine-readable zone. Check the details below, then save.")
        case .intelligence: String(localized: "Filled in on device with Apple Intelligence. Check the details below, then save.")
        case .text: kind == .custom
            ? String(localized: "Vault couldn’t tell what this is. Choose a type and fill in the details.")
            : String(localized: "Filled in from the text on your scan. Check the details below, then save.")
        }
    }
}

/// Choose which reminders to get before expiry.
struct ReminderOffsetsEditor: View {
    let kind: DocumentKind
    @Binding var offsets: [ReminderOffset]?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Use Defaults", isOn: Binding(
                        get: { offsets == nil },
                        set: { offsets = $0 ? nil : ReminderDefaults.offsets(for: kind) }
                    ))
                } footer: {
                    Text("Defaults: \(ReminderDefaults.offsets(for: kind).map(\.description).formatted(.list(type: .and))). Change them in Settings.")
                }
                Section("Remind Me") {
                    ForEach(ReminderOffset.choices.reversed()) { choice in
                        let selected = (offsets ?? ReminderDefaults.offsets(for: kind)).contains(choice)
                        Button {
                            var current = offsets ?? ReminderDefaults.offsets(for: kind)
                            if selected { current.removeAll { $0 == choice } } else { current.append(choice) }
                            offsets = current.sorted(by: >)
                        } label: {
                            HStack {
                                Text(choice.description)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
