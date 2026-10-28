import SwiftUI

/// Reviews items saved from the Share extension, one at a time.
struct InboxImportView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var items: [InboxImporter.Item] = []
    @State private var draft: DocumentDraft?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let draft, let item = items.first {
                DocumentEditorView(mode: .create(draft)) { _ in
                    InboxImporter.remove(item)
                }
                .id(item.id)
                .onDisappear { advance(removingCurrent: true) }
            } else if let item = items.first {
                AnalyzingView(pages: item.pages)
                    .task(id: item.id) { await prepare(item) }
            } else if didLoad {
                NavigationStack {
                    ContentUnavailableView("Nothing to Import", systemImage: "tray", description: Text("Use Save to Vault from the Share menu in Photos, Files, Mail or Safari."))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(role: .close) { dismiss() }
                            }
                        }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard !didLoad else { return }
            items = InboxImporter.loadItems()
            didLoad = true
        }
    }

    private func prepare(_ item: InboxImporter.Item) async {
        var next: DocumentDraft
        if item.pages.isEmpty {
            next = DocumentDraft(kind: DocumentKind(rawValue: item.manifest.kind ?? "") ?? .custom, personID: store.me()?.id)
        } else {
            let analysis = await ScanPipeline.analyze(item.pages)
            next = DocumentDraft(analysis: analysis, pages: item.pages, personID: store.me()?.id)
        }
        if let kind = item.manifest.kind.flatMap(DocumentKind.init(rawValue:)), kind != next.kind {
            next.changeKind(to: kind)
        }
        if !item.manifest.title.isEmpty {
            next.title = item.manifest.title
            next.titleWasEdited = true
        }
        if let link = item.manifest.link {
            next.notes = [next.notes, link.absoluteString].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        draft = next
    }

    private func advance(removingCurrent: Bool) {
        // The editor dismissed (saved or discarded): move to the next item, or finish.
        guard !items.isEmpty else { return }
        let current = items.removeFirst()
        if removingCurrent { InboxImporter.remove(current) }
        draft = nil
        if items.isEmpty { dismiss() }
    }
}
