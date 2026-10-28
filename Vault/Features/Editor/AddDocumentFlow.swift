import PhotosUI
import SwiftData
import SwiftUI

/// Capture → read → review → save. Opened from the "+" menu, the empty
/// state, the "Scan Document" Quick Action and the Share extension inbox.
struct AddDocumentFlow: View {
    let source: AppRouter.AddSource

    @Environment(VaultStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    enum Stage {
        case capturing
        case analyzing([PageSource])
        case review(DocumentDraft)
    }

    @State private var stage: Stage = .capturing
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImportingFiles = false

    var body: some View {
        Group {
            switch stage {
            case .capturing:
                capture
            case .analyzing(let pages):
                AnalyzingView(pages: pages)
                    .task { await analyze(pages) }
            case .review(let draft):
                DocumentEditorView(mode: .create(draft)) { document in
                    router.tab = .documents
                    router.documentsPath = [document.id]
                }
            }
        }
        .animation(.default, value: stageID)
    }

    private var stageID: Int {
        switch stage {
        case .capturing: 0
        case .analyzing: 1
        case .review: 2
        }
    }

    @ViewBuilder
    private var capture: some View {
        switch source {
        case .scan:
            if DocumentScannerView.isSupported {
                DocumentScannerView { images in
                    stage = images.isEmpty ? .capturing : .analyzing(images.map(PageSource.image))
                    if images.isEmpty { dismiss() }
                } onCancel: {
                    dismiss()
                }
                .ignoresSafeArea()
            } else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Camera Unavailable", systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text("Scanning needs a camera. You can import a photo or file instead.")
                    } actions: {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            Text("Choose from Photos")
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .toolbar { cancelButton }
                }
                .onChange(of: photoItems) { _, items in loadPhotos(items) }
            }
        case .photos:
            NavigationStack {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images) {
                    Text("Choose Photos")
                }
                .photosPickerStyle(.inline)
                .photosPickerDisabledCapabilities([.stagingArea])
                .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Choose Front, Then Back")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    cancelButton
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") { loadPhotos(photoItems) }
                            .disabled(photoItems.isEmpty)
                    }
                }
            }
        case .files:
            NavigationStack {
                ContentUnavailableView {
                    Label("Import from Files", systemImage: "folder")
                } description: {
                    Text("Choose images or PDFs. Vault keeps an encrypted copy; the original stays where it is.")
                } actions: {
                    Button("Choose Files") { isImportingFiles = true }
                        .buttonStyle(.glassProminent)
                }
                .toolbar { cancelButton }
            }
            .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    let pages = ImportLoader.load(urls: urls)
                    if !pages.isEmpty { stage = .analyzing(pages) }
                }
            }
            .onAppear { isImportingFiles = true }
        case .manual:
            TemplatePickerView(selection: nil) { kind in
                Task { @MainActor in
                    stage = .review(DocumentDraft(kind: kind, personID: store.me()?.id))
                }
            }
        }
    }

    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) { dismiss() }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            let pages = await ImportLoader.load(items: items)
            if !pages.isEmpty { stage = .analyzing(pages) }
        }
    }

    private func analyze(_ pages: [PageSource]) async {
        let analysis = await ScanPipeline.analyze(pages)
        stage = .review(DocumentDraft(analysis: analysis, pages: pages, personID: store.me()?.id))
    }
}

/// The loading state while Vault reads a scan.
struct AnalyzingView: View {
    let pages: [PageSource]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                if let preview = pages.first?.previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .overlay {
                            if !reduceMotion {
                                ScanLine()
                                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .shadow(radius: 12, y: 6)
                        .padding(.horizontal, 40)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading Your Document")
                        .font(.headline)
                    Text(IntelligenceExtractor.isAvailable
                        ? "Using Apple Intelligence on this iPhone. Nothing leaves your device."
                        : "Recognizing text on this iPhone. Nothing leaves your device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

private struct ScanLine: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, .accentColor.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
                .offset(y: phase * (proxy.size.height + 60) - 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { phase = 1 }
        }
    }
}
