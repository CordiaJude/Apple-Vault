import PhotosUI
import SwiftData
import SwiftUI

/// Family profiles. Documents belong to a person, so a family's passports,
/// licenses and insurance cards stay organized.
struct PeopleView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.createdAt)])
    private var people: [Person]
    @State private var editing: PersonEditorView.Mode?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.peoplePath) {
            ScrollView {
                if people.isEmpty {
                    ContentUnavailableView {
                        Label("No People", systemImage: "person.2")
                    } description: {
                        Text("Add yourself and your family to keep everyone’s documents organized.")
                    } actions: {
                        Button("Add Person") { editing = .create }
                            .buttonStyle(.glassProminent)
                    }
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(people) { person in
                            NavigationLink(value: person.id) {
                                PersonTile(person: person)
                            }
                            .buttonStyle(CardPressStyle())
                            .contextMenu {
                                Button {
                                    editing = .edit(person)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = .create
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PersonDetailView(personID: id)
            }
            .sheet(item: $editing) { mode in
                PersonEditorView(mode: mode)
            }
        }
    }
}

private struct PersonTile: View {
    let person: Person

    var body: some View {
        VStack(spacing: 10) {
            AvatarView(person: person, size: 72)
            VStack(spacing: 2) {
                Text(person.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(person.relationship.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("^[\(person.documents?.count ?? 0) document](inflect: true)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(person.color.color.opacity(0.15), in: .capsule)
                .foregroundStyle(person.color.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct PersonDetailView: View {
    let personID: UUID
    @Query private var matches: [Person]
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    init(personID: UUID) {
        self.personID = personID
        _matches = Query(filter: #Predicate<Person> { $0.id == personID })
    }

    var body: some View {
        if let person = matches.first {
            List {
                Section {
                    VStack(spacing: 12) {
                        AvatarView(person: person, size: 96)
                        Text(person.displayName)
                            .font(.title2.bold())
                        Text(person.relationship.name)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Documents") {
                    if person.activeDocuments.isEmpty {
                        Text("No documents yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(person.activeDocuments) { document in
                        NavigationLink {
                            DocumentDetailView(document: document)
                        } label: {
                            HStack(spacing: 14) {
                                DocumentGlyph(kind: document.kind, color: document.color)
                                VStack(alignment: .leading) {
                                    Text(document.title)
                                    Text(document.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if person.relationship != .me {
                    Section {
                        Button("Delete Person", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    } footer: {
                        Text("Their documents stay in Vault, unassigned.")
                    }
                }
            }
            .navigationTitle(person.firstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Edit") { isEditing = true }
            }
            .sheet(isPresented: $isEditing) {
                PersonEditorView(mode: .edit(person))
            }
            .confirmationDialog("Delete \(person.displayName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Person", role: .destructive) {
                    dismiss()
                    store.delete(person)
                }
            }
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

/// Create or edit a person: name, relationship, color and avatar (an emoji or
/// a photo).
struct PersonEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(Person)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let person): person.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(VaultStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allPeople: [Person]

    @State private var name = ""
    @State private var relationship: Relationship = .partner
    @State private var color: CardColor = .purple
    @State private var emoji = ""
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var didLoad = false
    @State private var saveCount = 0

    private static let suggestedEmoji = ["🙂", "😎", "🧑‍💻", "👩", "👨", "👧", "👦", "👶", "👵", "👴", "🐶", "🌟"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        AvatarView(color: color, emoji: emoji, initials: initials, photo: photo, size: 96)
                            .animation(.default, value: emoji)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photo == nil ? "Choose Photo" : "Change Photo")
                        }
                        .buttonStyle(.glass)
                        if photo != nil {
                            Button("Remove Photo", role: .destructive) { photo = nil }
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                    Picker("Relationship", selection: $relationship) {
                        ForEach(Relationship.allCases) { relationship in
                            Label(relationship.name, systemImage: relationship.symbol).tag(relationship)
                        }
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $color)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.suggestedEmoji, id: \.self) { candidate in
                                Button {
                                    emoji = emoji == candidate ? "" : candidate
                                } label: {
                                    Text(candidate)
                                        .font(.title)
                                        .frame(width: 48, height: 48)
                                        .background(emoji == candidate ? color.color.opacity(0.25) : Color.clear, in: .circle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    TextField("Or type any emoji", text: $emoji)
                        .onChange(of: emoji) { _, value in
                            if value.count > 1 { emoji = String(value.suffix(1)) }
                        }
                } header: {
                    Text("Avatar")
                } footer: {
                    Text("Shown when there’s no photo. Use the emoji keyboard for Memoji-style faces.")
                }
            }
            .navigationTitle(isCreating ? "New Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty && relationship != .me)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photo = image
                    }
                }
            }
            .onAppear(perform: load)
            .sensoryFeedback(.success, trigger: saveCount)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if case .edit(let person) = mode {
            name = person.name
            relationship = person.relationship
            color = person.color
            emoji = person.emoji
            photo = person.photo
        } else {
            let used = Set(allPeople.map(\.color))
            color = CardColor.allCases.first { !used.contains($0) } ?? .purple
            relationship = allPeople.contains { $0.relationship == .me } ? .partner : .me
        }
    }

    private func save() {
        let person: Person
        switch mode {
        case .create:
            person = Person(name: "", relationship: relationship, color: color, sortOrder: (allPeople.map(\.sortOrder).max() ?? 0) + 1)
            modelContext.insert(person)
        case .edit(let existing):
            person = existing
        }
        person.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        person.relationship = relationship
        person.color = color
        person.emoji = emoji
        person.photo = photo
        store.vaultDidChange()
        saveCount += 1
        dismiss()
    }
}

/// A row of color dots, like the color picker in Reminders.
struct ColorSwatchPicker: View {
    @Binding var selection: CardColor
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CardColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selection == color {
                                Circle().strokeBorder(.background, lineWidth: 3)
                                Circle().strokeBorder(color.color, lineWidth: 1.5).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
