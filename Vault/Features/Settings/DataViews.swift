import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export selected documents (or everything) as one PDF, optionally
/// password-protected.
struct ExportView: View {
    @Query(sort: \VaultDocument.title) private var documents: [VaultDocument]
    @Environment(AppLock.self) private var lock
    @State private var selection: Set<UUID> = []
    @State private var usePassword = true
    @State private var password = ""
    @State private var includeFields = true
    @State private var shareItem: ShareItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Protect with Password", isOn: $usePassword)
                if usePassword {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                }
                Toggle("Include Typed Details", isOn: $includeFields)
            } footer: {
                Text("Anyone with the PDF can read it. A password keeps it encrypted until opened.")
            }

            Section {
                Button(selection.count == documents.count ? "Deselect All" : "Select All") {
                    selection = selection.count == documents.count ? [] : Set(documents.map(\.id))
                }
                ForEach(documents) { document in
                    Button {
                        if selection.contains(document.id) { selection.remove(document.id) } else { selection.insert(document.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.contains(document.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection.contains(document.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            DocumentGlyph(kind: document.kind, color: document.color)
                            Text(document.title).foregroundStyle(.primary)
                        }
                    }
                    .accessibilityAddTraits(selection.contains(document.id) ? .isSelected : [])
                }
            } header: {
                Text("Documents")
            }
        }
        .navigationTitle("Export as PDF")
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView("Nothing to Export", systemImage: "doc.richtext", description: Text("Add a document first."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    Button("Export", action: export)
                        .disabled(selection.isEmpty || (usePassword && password.count < 4))
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]).ignoresSafeArea()
        }
        .alert("Couldn’t Export", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export() {
        Task {
            guard await lock.authenticate(reason: String(localized: "Export your documents")) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let chosen = documents.filter { selection.contains($0.id) }
                let url = try ExportService.pdf(for: chosen, password: usePassword ? password : nil, includeFields: includeFields)
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Encrypted backup to a file in Files, and restore from one.
struct BackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(VaultStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(HUDCenter.self) private var hud

    @State private var password = ""
    @State private var confirmation = ""
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var restoreURL: URL?
    @State private var restorePassword = ""
    @State private var isWorking = false
    @State private var message: (title: String, body: String)?

    var body: some View {
        Form {
            Section {
                SecureField("Backup Password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Verify Password", text: $confirmation)
                    .textContentType(.newPassword)
                Button {
                    makeBackup()
                } label: {
                    HStack {
                        Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                        if isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(password.count < 8 || password != confirmation || isWorking)
            } header: {
                Text("Back Up")
            } footer: {
                Text("Creates one encrypted file with every document, image and person. Use at least 8 characters, and keep the password somewhere safe: without it, the backup can’t be opened.")
            }

            Section {
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Documents already in Vault are kept; only missing ones are added.")
            }
        }
        .navigationTitle("Backup & Restore")
        .fileExporter(isPresented: $isExporting, item: exportURL.map(BackupFile.init), contentTypes: [.vaultBackup], defaultFilename: exportURL?.lastPathComponent) { result in
            if case .success = result { hud.show(String(localized: "Backup Saved"), symbol: "externaldrive.fill.badge.checkmark") }
            password = ""
            confirmation = ""
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.vaultBackup, .data]) { result in
            if case .success(let url) = result { restoreURL = url }
        }
        .alert("Enter Backup Password", isPresented: Binding(get: { restoreURL != nil }, set: { if !$0 { restoreURL = nil } })) {
            SecureField("Password", text: $restorePassword)
            Button("Restore") { restore() }
            Button("Cancel", role: .cancel) { restorePassword = "" }
        }
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message?.body ?? "")
        }
    }

    private func makeBackup() {
        Task {
            guard await lock.authenticate(reason: String(localized: "Back up your documents")) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                exportURL = try BackupService.makeBackup(context: modelContext, password: password)
                isExporting = true
            } catch {
                message = (String(localized: "Backup Failed"), error.localizedDescription)
            }
        }
    }

    private func restore() {
        guard let url = restoreURL else { return }
        let password = restorePassword
        restorePassword = ""
        restoreURL = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let summary = try BackupService.restore(from: url, password: password, context: modelContext)
            store.vaultDidChange(immediately: true)
            message = (String(localized: "Restore Complete"),
                       String(localized: "Added \(summary.documents) documents and \(summary.people) people. \(summary.skipped) were already in Vault."))
        } catch {
            message = (String(localized: "Restore Failed"), error.localizedDescription)
        }
    }
}

/// Wraps a finished backup file for `fileExporter`.
struct BackupFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .vaultBackup) { file in
            SentTransferredFile(file.url)
        }
    }
}

/// About & Privacy, stated plainly.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Text("Vault")
                        .font(.title.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Your Privacy") {
                PrivacyRow(symbol: "iphone", title: "Stays on Your iPhone",
                           text: "Your documents never leave this device unless you share or export them, or turn on iCloud sync.")
                PrivacyRow(symbol: "wifi.slash", title: "No Network, No Analytics",
                           text: "Vault makes no network connections and collects no analytics, tracking or crash data. The only exception is iCloud sync, which is off unless you turn it on.")
                PrivacyRow(symbol: "lock.doc", title: "Encrypted at Rest",
                           text: "Images, PDFs, numbers, notes and scanned text are encrypted with AES-256 using a key kept in the Keychain on this device only, and stored with iOS Data Protection, so nothing is readable while your iPhone is locked.")
                PrivacyRow(symbol: "faceid", title: "Locked by Face ID",
                           text: "Vault locks when you leave, hides itself in the App Switcher and while your screen is recorded, and asks again before revealing a hidden number.")
                PrivacyRow(symbol: "apple.intelligence", title: "On-Device Intelligence",
                           text: "Text recognition and Apple Intelligence run entirely on your iPhone.")
                PrivacyRow(symbol: "rectangle.on.rectangle", title: "Widgets Show Names Only",
                           text: "Widgets, Siri, Control Center and Spotlight see document names and dates only, never numbers or images.")
            }
        }
        .navigationTitle("About & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
