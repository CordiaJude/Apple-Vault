import SwiftData
import SwiftUI

/// Settings, opened from the gear button on every tab.
struct SettingsView: View {
    @Environment(AppLock.self) private var lock
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKey.spotlight) private var spotlightEnabled = false
    @AppStorage(SettingsKey.iCloudSync) private var iCloudSyncEnabled = false
    @State private var syncError: String?
    @State private var isConfirmingSampleReset = false

    var body: some View {
        @Bindable var lock = lock

        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { lock.lockEnabled },
                        set: { newValue in
                            Task {
                                // Turning the lock off requires proving you can unlock it.
                                if newValue || (await lock.authenticate(reason: String(localized: "Turn off \(lock.biometryName) for Vault"))) {
                                    lock.lockEnabled = newValue
                                }
                            }
                        }
                    )) {
                        Label("Require \(lock.biometryName)", systemImage: lock.biometrySymbol)
                    }
                    if lock.lockEnabled {
                        Picker(selection: $lock.timeout) {
                            ForEach(AppLock.Timeout.allCases) { timeout in
                                Text(timeout.name).tag(timeout)
                            }
                        } label: {
                            Label("Auto-Lock", systemImage: "lock.rotation")
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    if lock.deviceHasNoPasscode {
                        Text("This iPhone has no passcode, so Vault can’t lock and iOS can’t encrypt your files. Set a passcode in Settings ▸ Face ID & Passcode.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Vault locks when you leave it, and always asks again before revealing a hidden number or opening a document from Siri, widgets or Control Center.")
                    }
                }

                Section {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        Label("Reminders", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        ManagePeopleView()
                    } label: {
                        Label("People", systemImage: "person.2")
                    }
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("Categories", systemImage: "folder")
                    }
                }

                Section {
                    if FeatureFlags.cloudKitCompiledIn {
                        Toggle(isOn: Binding(get: { iCloudSyncEnabled }, set: { setSync($0) })) {
                            Label("iCloud Sync", systemImage: "icloud")
                        }
                    } else {
                        LabeledContent {
                            Text("Off")
                        } label: {
                            Label("iCloud Sync", systemImage: "icloud.slash")
                        }
                    }
                    Toggle(isOn: $spotlightEnabled) {
                        Label("Show in Spotlight", systemImage: "magnifyingglass")
                    }
                    .onChange(of: spotlightEnabled) { _, enabled in
                        if enabled {
                            let documents = (try? modelContext.fetch(FetchDescriptor<VaultDocument>())) ?? []
                            SpotlightIndexer.index(documents)
                        } else {
                            SpotlightIndexer.removeAll()
                        }
                    }
                } header: {
                    Text("Sync & Search")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if FeatureFlags.cloudKitCompiledIn {
                            Text("iCloud sync keeps documents end-to-end encrypted with your vault key, which syncs through iCloud Keychain.")
                        } else {
                            Text("iCloud sync isn’t available in this build. It needs a paid Apple Developer account; Vault works fully without it.")
                        }
                        Text("Spotlight shows document titles only, never numbers or contents. Opening a result still asks for \(lock.biometryName).")
                    }
                }

                Section("Your Data") {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Backup & Restore", systemImage: "externaldrive")
                    }
                }

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("About & Privacy", systemImage: "hand.raised")
                    }
                }

                #if DEBUG
                Section {
                    Button("Reset Sample Data", role: .destructive) {
                        isConfirmingSampleReset = true
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. Replaces everything in Vault with sample documents.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .alert("iCloud Sync", isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
                Button("OK") {}
            } message: {
                Text(syncError ?? "")
            }
            #if DEBUG
            .confirmationDialog("Replace everything with sample data?", isPresented: $isConfirmingSampleReset, titleVisibility: .visible) {
                Button("Reset Sample Data", role: .destructive) {
                    SampleData.reset(in: modelContext)
                    store.vaultDidChange(immediately: true)
                }
            }
            #endif
        }
    }

    private func setSync(_ enabled: Bool) {
        do {
            try store.setICloudSync(enabled)
            iCloudSyncEnabled = enabled
        } catch {
            syncError = error.localizedDescription
        }
    }
}

// MARK: - Reminders

struct ReminderSettingsView: View {
    @State private var passport = ReminderDefaults.passport
    @State private var other = ReminderDefaults.other
    @State private var hour = ReminderDefaults.hour
    @Environment(VaultStore.self) private var store

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    OffsetChecklist(title: String(localized: "Passports"), offsets: $passport)
                } label: {
                    LabeledContent("Passports", value: passport.map(\.description).formatted(.list(type: .and)))
                }
                NavigationLink {
                    OffsetChecklist(title: String(localized: "Everything Else"), offsets: $other)
                } label: {
                    LabeledContent("Everything Else", value: other.map(\.description).formatted(.list(type: .and)))
                }
            } header: {
                Text("Default Reminders")
            } footer: {
                Text("Many countries require six months of passport validity to enter, so passports remind you at 9 and 6 months by default. You can change reminders for any document in its Edit screen.")
            }
            Section("Time of Day") {
                Picker("Remind At", selection: $hour) {
                    ForEach(6..<22, id: \.self) { hour in
                        Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened))
                            .tag(hour)
                    }
                }
            }
        }
        .navigationTitle("Reminders")
        .onChange(of: passport) { _, value in ReminderDefaults.passport = value; store.vaultDidChange() }
        .onChange(of: other) { _, value in ReminderDefaults.other = value; store.vaultDidChange() }
        .onChange(of: hour) { _, value in ReminderDefaults.hour = value; store.vaultDidChange() }
    }
}

private struct OffsetChecklist: View {
    let title: String
    @Binding var offsets: [ReminderOffset]

    var body: some View {
        List(ReminderOffset.choices.reversed()) { choice in
            let selected = offsets.contains(choice)
            Button {
                if selected { offsets.removeAll { $0 == choice } } else { offsets.append(choice) }
                offsets.sort(by: >)
            } label: {
                HStack {
                    Text(choice.description).foregroundStyle(.primary)
                    Spacer()
                    if selected { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .navigationTitle(title)
    }
}

// MARK: - People

struct ManagePeopleView: View {
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.createdAt)]) private var people: [Person]
    @Environment(VaultStore.self) private var store
    @State private var editing: PersonEditorView.Mode?

    var body: some View {
        List {
            ForEach(people) { person in
                Button {
                    editing = .edit(person)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(person: person, size: 36)
                        VStack(alignment: .leading) {
                            Text(person.displayName).foregroundStyle(.primary)
                            Text(person.relationship.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onMove { from, to in
                var ordered = people
                ordered.move(fromOffsets: from, toOffset: to)
                for (index, person) in ordered.enumerated() { person.sortOrder = index }
                store.vaultDidChange()
            }
            .onDelete { offsets in
                for index in offsets where people[index].relationship != .me {
                    store.delete(people[index])
                }
            }
        }
        .navigationTitle("People")
        .toolbar {
            EditButton()
            Button {
                editing = .create
            } label: {
                Label("Add Person", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { PersonEditorView(mode: $0) }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView("No People", systemImage: "person.2", description: Text("Add family members so their documents stay organized."))
            }
        }
    }
}

// MARK: - Categories

struct CategoriesView: View {
    @Query(sort: \DocumentCategory.sortOrder) private var categories: [DocumentCategory]
    @Environment(\.modelContext) private var modelContext
    @Environment(VaultStore.self) private var store
    @State private var newName = ""
    @State private var renaming: DocumentCategory?
    @State private var renameText = ""

    private static let symbols = ["folder", "briefcase", "graduationcap", "pawprint", "building.2", "creditcard", "gift", "airplane", "heart", "star", "house", "car"]

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    HStack {
                        Menu {
                            ForEach(Self.symbols, id: \.self) { symbol in
                                Button { category.symbol = symbol; store.vaultDidChange() } label: { Label(symbol, systemImage: symbol) }
                            }
                        } label: {
                            Image(systemName: category.symbol)
                                .frame(width: 28)
                                .foregroundStyle(.tint)
                        }
                        .accessibilityLabel("Change Symbol")
                        Text(category.name)
                        Spacer()
                        Text("\(category.documents?.count ?? 0)")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Rename") {
                            renameText = category.name
                            renaming = category
                        }
                        .tint(.blue)
                    }
                }
                .onMove { from, to in
                    var ordered = categories
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (index, category) in ordered.enumerated() { category.sortOrder = index }
                    store.vaultDidChange()
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(categories[index]) }
                    store.vaultDidChange()
                }
            } footer: {
                Text("Deleting a category keeps its documents; they move to Other.")
            }
            Section {
                HStack {
                    TextField("New Category", text: $newName)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar { EditButton() }
        .alert("Rename Category", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                renaming?.name = renameText
                store.vaultDidChange()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(DocumentCategory(name: name, symbol: "folder", sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1))
        newName = ""
        store.vaultDidChange()
    }
}
