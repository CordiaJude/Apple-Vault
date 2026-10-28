import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(VaultStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Documents", systemImage: "wallet.pass", value: AppRouter.Tab.documents) {
                DocumentsView()
            }
            Tab("Expiring", systemImage: "calendar.badge.clock", value: AppRouter.Tab.expiring) {
                ExpiringView()
            }
            Tab("People", systemImage: "person.2", value: AppRouter.Tab.people) {
                PeopleView()
            }
            Tab(value: AppRouter.Tab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsView()
        }
        .sheet(item: $router.addSource) { source in
            AddDocumentFlow(source: source)
        }
        .sheet(isPresented: $router.pendingInboxImport) {
            InboxImportView()
        }
        .fullScreenCover(item: presentedDocument) { document in
            PresentModeView(document: document)
        }
    }

    private var presentedDocument: Binding<VaultDocument?> {
        Binding(
            get: { router.presentedDocumentID.flatMap { store.document(id: $0) } },
            set: { router.presentedDocumentID = $0?.id }
        )
    }
}

/// The toolbar button that opens Settings, shared by every tab.
struct SettingsToolbarButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.isShowingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

/// The "+" menu: scan, import from Photos or Files, or start from a template.
struct AddDocumentMenu: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            Button {
                router.addSource = .scan
            } label: {
                Label("Scan Document", systemImage: "doc.viewfinder")
            }
            Button {
                router.addSource = .photos
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                router.addSource = .files
            } label: {
                Label("Import from Files", systemImage: "folder")
            }
            Divider()
            Button {
                router.addSource = .manual
            } label: {
                Label("Enter Manually", systemImage: "square.and.pencil")
            }
        } label: {
            Label("Add Document", systemImage: "plus")
        }
        .menuIndicator(.hidden)
    }
}
