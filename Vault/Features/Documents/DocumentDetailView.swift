import SwiftData
import SwiftUI

/// A single document: its card (tap to flip), the fields (tap to copy,
/// sensitive numbers masked until Face ID), expiration and renewal, pages,
/// notes and tags.
struct DocumentDetailView: View {
    @Bindable var document: VaultDocument

    @Environment(VaultStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @Environment(HUDCenter.self) private var hud
    @Environment(ScreenCaptureMonitor.self) private var captureMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var revealedFields: Set<UUID> = []
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var shareItem: ShareItem?
    @State private var isAddingEvent = false
    @State private var viewerPage: DocumentPage?
    @State private var errorMessage: String?
    @State private var copyCount = 0
    @State private var deleteCount = 0

    var body: some View {
        let payload = document.payload

        List {
            Section {
                CardHeroView(document: document)
                    .hiddenWhileCaptured(captureMonitor)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                actionButtons
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .listSectionSeparator(.hidden)

            if payload.fields.contains(where: { !$0.isEmpty }) {
                Section {
                    ForEach(payload.fields.filter { !$0.isEmpty }) { field in
                        FieldRow(
                            field: field,
                            isRevealed: revealedFields.contains(field.id),
                            isCaptured: captureMonitor.isCaptured,
                            onCopy: { copy(field) },
                            onToggleReveal: { toggleReveal(field) }
                        )
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Tap a field to copy it. Copied numbers are cleared from the clipboard after a minute.")
                }
            }

            if document.expiresOn != nil || document.kind.usuallyExpires {
                ExpirationSection(document: document, isAddingEvent: $isAddingEvent, errorMessage: $errorMessage)
            }

            if !document.sortedPages.isEmpty {
                Section("Pages") {
                    PageStrip(pages: document.sortedPages) { viewerPage = $0 }
                        .hiddenWhileCaptured(captureMonitor)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }

            if !payload.notes.isEmpty {
                Section("Notes") {
                    Text(payload.notes)
                        .textSelection(.enabled)
                        .redacted(reason: captureMonitor.isCaptured ? .placeholder : [])
                }
            }

            Section {
                if !document.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(document.tags.map { "#" + $0 }.joined(separator: " "))
                    }
                }
                if let person = document.person {
                    LabeledContent("Belongs To") {
                        HStack(spacing: 6) {
                            AvatarView(person: person, size: 22)
                            Text(person.displayName)
                        }
                    }
                }
                if let category = document.category {
                    LabeledContent("Category") {
                        Label(category.name, systemImage: category.symbol)
                    }
                }
                LabeledContent("Added", value: document.createdAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Last Edited", value: document.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .foregroundStyle(.secondary)

            Section {
                Button("Delete Document", role: .destructive) {
                    isConfirmingDelete = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $isEditing) {
            DocumentEditorView(mode: .edit(document))
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isAddingEvent) {
            if let expiry = document.expiresOn {
                EventEditView(
                    title: String(localized: "\(document.title) expires"),
                    date: expiry,
                    notes: document.renewalURL.map { String(localized: "Renew at \($0.absoluteString)") }
                ) { saved in
                    isAddingEvent = false
                    if saved { hud.show(String(localized: "Added to Calendar"), symbol: "calendar.badge.checkmark") }
                }
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $viewerPage) { page in
            PageViewer(pages: document.sortedPages, initial: page)
        }
        .confirmationDialog("Delete “\(document.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Document", role: .destructive) {
                deleteCount += 1
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    store.delete(document)
                }
            }
        } message: {
            Text("This deletes the document, its images and its reminders from this iPhone.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .sensoryFeedback(.warning, trigger: deleteCount)
        .onDisappear { revealedFields.removeAll() }
        .onChange(of: lock.isLocked) { _, locked in
            if locked { revealedFields.removeAll() }
        }
    }

    // MARK: Actions row

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(title: String(localized: "Present"), symbol: "rectangle.portrait.and.arrow.forward", prominent: true) {
                    router.presentedDocumentID = document.id
                }
                ActionButton(title: String(localized: "Share"), symbol: "square.and.arrow.up") {
                    share(asPDF: false)
                }
                if let url = document.renewalURL, document.expiresOn != nil {
                    ActionButton(title: String(localized: "Renew"), symbol: "arrow.clockwise") {
                        openURL(url)
                    }
                } else {
                    ActionButton(title: String(localized: "Edit"), symbol: "pencil") {
                        isEditing = true
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                document.isFavorite.toggle()
                store.vaultDidChange()
            } label: {
                Label(document.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: document.isFavorite ? "star.fill" : "star")
            }
            .sensoryFeedback(.selection, trigger: document.isFavorite)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    Button { share(asPDF: false) } label: { Label("Share as Image", systemImage: "photo") }
                    Button { share(asPDF: true) } label: { Label("Share as PDF", systemImage: "doc.richtext") }
                }
                if document.expiresOn != nil {
                    Section {
                        Button { isAddingEvent = true } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        Button { addReminder() } label: { Label("Add to Reminders", systemImage: "checklist") }
                    }
                }
                Section {
                    Button(role: .destructive) { isConfirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") { isEditing = true }
        }
    }

    // MARK: Behaviors

    private func copy(_ field: DocumentField) {
        Clipboard.copy(field.value, sensitive: field.isSensitive || document.kind.isHighlySensitive)
        copyCount += 1
        hud.show(String(localized: "Copied \(field.label)"), symbol: "doc.on.doc.fill")
    }

    private func toggleReveal(_ field: DocumentField) {
        if revealedFields.contains(field.id) {
            revealedFields.remove(field.id)
            return
        }
        Task {
            if await lock.authenticate(reason: String(localized: "Show your \(field.label)")) {
                withAnimation { _ = revealedFields.insert(field.id) }
            }
        }
    }

    private func share(asPDF: Bool) {
        do {
            let url = asPDF ? try ExportService.pdf(for: document) : try ExportService.image(for: document)
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addReminder() {
        guard let expiry = document.expiresOn else { return }
        Task {
            do {
                try await RemindersService.addRenewalReminder(title: document.title, expiry: expiry, url: document.renewalURL)
                hud.show(String(localized: "Added to Reminders"), symbol: "checklist.checked")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A compact glass button with an icon over a caption, used in the action row.
struct ActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(height: 24)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(ActionButtonStyle(prominent: prominent))
    }
}

private struct ActionButtonStyle: PrimitiveButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 18))
        }
    }
}

// MARK: - Field row

struct FieldRow: View {
    let field: DocumentField
    let isRevealed: Bool
    let isCaptured: Bool
    let onCopy: () -> Void
    let onToggleReveal: () -> Void

    private var isMasked: Bool { field.isSensitive && (!isRevealed || isCaptured) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(isMasked ? field.maskedValue : field.displayValue)
                        .font(field.kind == .identifier ? .body.monospaced() : .body)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .multilineTextAlignment(.leading)
                        .privacySensitive(field.isSensitive)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(field.label)
            .accessibilityValue(isMasked ? String(localized: "Hidden") : field.displayValue)
            .accessibilityHint("Double-tap to copy")

            if field.isSensitive {
                Button(action: onToggleReveal) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isRevealed ? "Hide \(field.label)" : "Show \(field.label)")
            } else if field.kind == .phone, let url = URL(string: "tel:" + field.value.filter { $0.isNumber || $0 == "+" }) {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Call \(field.displayValue)")
            }
        }
        .contextMenu {
            Button { onCopy() } label: { Label("Copy", systemImage: "doc.on.doc") }
            if field.isSensitive {
                Button { onToggleReveal() } label: {
                    Label(isRevealed ? "Hide" : "Show", systemImage: isRevealed ? "eye.slash" : "eye")
                }
            }
        }
    }
}

// MARK: - Expiration

private struct ExpirationSection: View {
    @Bindable var document: VaultDocument
    @Binding var isAddingEvent: Bool
    @Binding var errorMessage: String?
    @Environment(\.openURL) private var openURL
    @Environment(HUDCenter.self) private var hud

    var body: some View {
        Section {
            if let expiry = document.expiresOn {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.expiryStatus == .expired ? "Expired" : "Expires")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(expiry.formatted(date: .long, time: .omitted))
                    }
                    Spacer()
                    ExpiryBadge(date: expiry)
                }
                .accessibilityElement(children: .combine)

                if document.remindersEnabled {
                    LabeledContent("Reminders") {
                        Text(document.reminderOffsets.map(\.description).formatted(.list(type: .and)))
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    LabeledContent("Reminders", value: String(localized: "Off"))
                }

                Button {
                    isAddingEvent = true
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
                Button {
                    Task {
                        do {
                            try await RemindersService.addRenewalReminder(title: document.title, expiry: expiry, url: document.renewalURL)
                            hud.show(String(localized: "Added to Reminders"), symbol: "checklist.checked")
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Add to Reminders", systemImage: "checklist")
                }
                if let url = document.renewalURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack {
                            Label("Renew Online", systemImage: "safari")
                            Spacer()
                            Text(url.host() ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No expiration date. Add one in Edit to get reminders before it expires.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Expiration")
        } footer: {
            if document.kind == .passport, document.expiresOn != nil {
                Text("Many countries require at least six months of passport validity to enter.")
            }
        }
    }
}

struct ExpiryBadge: View {
    let date: Date

    var body: some View {
        let status = ExpiryStatus(expiresOn: date)
        Text(relative)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color(status).opacity(0.15), in: .capsule)
            .foregroundStyle(color(status))
    }

    private var relative: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days == 0 { return String(localized: "Today") }
        if days < 0 { return String(localized: "\(-days) days ago") }
        if days < 60 { return String(localized: "In \(days) days") }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func color(_ status: ExpiryStatus) -> Color {
        switch status {
        case .expired: .red
        case .soon: .orange
        case .upcoming: .yellow
        default: .green
        }
    }
}

// MARK: - Pages

private struct PageStrip: View {
    let pages: [DocumentPage]
    let onSelect: (DocumentPage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(pages) { page in
                    Button {
                        onSelect(page)
                    } label: {
                        VStack(spacing: 6) {
                            PageThumbnail(page: page)
                                .frame(height: 120)
                            Text(page.isPDF ? String(localized: "PDF") : page.role.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(page.isPDF ? Text("PDF page") : Text(page.role.name))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct PageThumbnail: View {
    let page: DocumentPage
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(page.aspectRatio, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if page.isPDF {
                Image(systemName: "doc.richtext.fill")
                    .font(.caption)
                    .padding(5)
                    .background(.thinMaterial, in: .circle)
                    .padding(4)
            }
        }
        .task(id: page.id) { image = page.thumbnail() }
    }
}

/// Full-screen pages with zoom and pan; PDFs open in PDFKit.
struct PageViewer: View {
    let pages: [DocumentPage]
    @State var initial: DocumentPage
    @Environment(\.dismiss) private var dismiss
    @Environment(ScreenCaptureMonitor.self) private var captureMonitor

    var body: some View {
        NavigationStack {
            TabView(selection: $initial) {
                ForEach(pages) { page in
                    PageContent(page: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .automatic : .never))
            .background(Color(.systemBackground))
            .overlay {
                if captureMonitor.isCaptured { CaptureBlockedView().background(.background) }
            }
            .navigationTitle(initial.isPDF ? String(localized: "PDF") : initial.role.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

private struct PageContent: View {
    let page: DocumentPage
    @State private var data: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if page.isPDF, let data {
                PDFKitView(data: data)
            } else if let image {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
            }
        }
        .task(id: page.id) {
            if page.isPDF {
                data = page.data()
            } else {
                image = page.image()
            }
        }
    }
}
