import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Save to Vault" from Photos, Files, Mail and Safari.
///
/// The extension never reads the vault and never needs the encryption key: it
/// drops what you shared into the App Group inbox (Data Protection: Complete),
/// and Vault imports, encrypts and removes it the next time you unlock it.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor @Observable
final class ShareModel {
    struct Attachment: Identifiable {
        let id = UUID()
        var data: Data
        var isPDF: Bool
        var preview: UIImage?
    }

    private weak var context: NSExtensionContext?
    var attachments: [Attachment] = []
    var link: URL?
    var title = ""
    var isLoading = true
    var isSaving = false
    var errorMessage: String?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var canSave: Bool { AppGroup.isAvailable && (!attachments.isEmpty || link != nil) && !isSaving }

    func load() async {
        defer { isLoading = false }
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               let data = await loadData(provider, type: .pdf) {
                attachments.append(Attachment(data: data, isPDF: true, preview: nil))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = await loadData(provider, type: .image), let image = UIImage(data: data) {
                let jpeg = image.jpegData(compressionQuality: 0.9) ?? data
                attachments.append(Attachment(data: jpeg, isPDF: false, preview: image.preparingThumbnail(of: CGSize(width: 400, height: 400))))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = await loadURL(provider) {
                if url.isFileURL, let data = try? Data(contentsOf: url) {
                    let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
                    if isPDF || UIImage(data: data) != nil {
                        attachments.append(Attachment(data: data, isPDF: isPDF, preview: isPDF ? nil : UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 400, height: 400))))
                    }
                } else {
                    link = url
                    if title.isEmpty { title = url.host() ?? "" }
                }
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { @Sendable data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    func save() {
        guard let inbox = AppGroup.inboxURL else {
            errorMessage = String(localized: "Save to Vault needs App Groups, which aren’t set up in this build.")
            return
        }
        isSaving = true
        do {
            let id = UUID()
            let folder = inbox.appending(path: id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            var files: [InboxManifest.File] = []
            for (index, attachment) in attachments.enumerated() {
                let name = "\(index).\(attachment.isPDF ? "pdf" : "jpg")"
                try attachment.data.write(to: folder.appending(path: name), options: [.atomic, .completeFileProtection])
                files.append(.init(name: name, isPDF: attachment.isPDF))
            }
            let manifest = InboxManifest(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), kind: nil, files: files, link: link, createdAt: .now)
            try JSONEncoder.vault.encode(manifest).write(to: folder.appending(path: InboxManifest.fileName), options: [.atomic, .completeFileProtection])
            context?.completeRequest(returningItems: nil)
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                if !AppGroup.isAvailable {
                    Section {
                        Label("Save to Vault isn’t available in this build because App Groups are turned off.", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if model.attachments.isEmpty && model.link == nil {
                        Text("There’s nothing here Vault can save. Share a photo, image or PDF.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(model.attachments) { attachment in
                                    Group {
                                        if let preview = attachment.preview {
                                            Image(uiImage: preview).resizable().scaledToFit()
                                        } else {
                                            Image(systemName: "doc.richtext.fill")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 80)
                                        }
                                    }
                                    .frame(height: 110)
                                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                                }
                                if let link = model.link {
                                    Label(link.host() ?? link.absoluteString, systemImage: "link")
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("Title (optional)", text: $model.title)
                } footer: {
                    Text("Vault will read the document and ask you to confirm its details the next time you open it. Until then it waits, protected, on this iPhone.")
                }
            }
            .navigationTitle("Save to Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save() }
                        .disabled(!model.canSave)
                }
            }
            .alert("Couldn’t Save", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}
