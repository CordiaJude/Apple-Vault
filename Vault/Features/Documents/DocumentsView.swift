import SwiftData
import SwiftUI

/// The Documents tab: a Wallet-style stack of cards, grouped by person and
/// then by category.
struct DocumentsView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: [SortDescriptor(\VaultDocument.sortOrder), SortDescriptor(\VaultDocument.title)])
    private var documents: [VaultDocument]
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.createdAt)])
    private var people: [Person]
    @Query(sort: \DocumentCategory.sortOrder) private var categories: [DocumentCategory]

    @Namespace private var cardNamespace
    @State private var personFilter: UUID?

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.documentsPath) {
            ScrollView {
                if documents.isEmpty {
                    EmptyDocumentsView()
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
                } else {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(sections) { section in
                            PersonCardSection(section: section, namespace: cardNamespace)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Documents")
            .toolbar {
                if people.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        personFilterMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddDocumentMenu()
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                DocumentDetailLoader(id: id)
                    .navigationTransition(.zoom(sourceID: id, in: cardNamespace))
            }
        }
    }

    private var personFilterMenu: some View {
        Menu {
            Picker("Show", selection: $personFilter) {
                Label("Everyone", systemImage: "person.2").tag(UUID?.none)
                ForEach(people) { person in
                    Text(person.displayName).tag(UUID?.some(person.id))
                }
            }
        } label: {
            Label("Filter", systemImage: personFilter == nil
                ? "line.3.horizontal.decrease"
                : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // MARK: Grouping

    struct CategoryGroup: Identifiable {
        var id: String
        var name: String
        var symbol: String
        var documents: [VaultDocument]
    }

    struct PersonSectionModel: Identifiable {
        var id: String
        var person: Person?
        var groups: [CategoryGroup]
        var count: Int { groups.reduce(0) { $0 + $1.documents.count } }
    }

    private var sections: [PersonSectionModel] {
        var result: [PersonSectionModel] = []
        let visiblePeople = personFilter.map { id in people.filter { $0.id == id } } ?? people
        let ordered = visiblePeople.sorted { ($0.relationship == .me ? 0 : 1, $0.sortOrder) < ($1.relationship == .me ? 0 : 1, $1.sortOrder) }
        for person in ordered {
            let theirs = documents.filter { $0.person?.id == person.id }
            guard !theirs.isEmpty else { continue }
            result.append(PersonSectionModel(id: person.id.uuidString, person: person, groups: group(theirs)))
        }
        if personFilter == nil {
            let unassigned = documents.filter { $0.person == nil }
            if !unassigned.isEmpty {
                result.append(PersonSectionModel(id: "unassigned", person: nil, groups: group(unassigned)))
            }
        }
        return result
    }

    private func group(_ documents: [VaultDocument]) -> [CategoryGroup] {
        let byCategory = Dictionary(grouping: documents) { $0.category?.id }
        var groups: [CategoryGroup] = categories.compactMap { category in
            guard let docs = byCategory[category.id], !docs.isEmpty else { return nil }
            return CategoryGroup(id: category.id.uuidString, name: category.name, symbol: category.symbol, documents: sortedForStack(docs))
        }
        if let uncategorized = byCategory[nil], !uncategorized.isEmpty {
            groups.append(CategoryGroup(id: "none", name: String(localized: "Other"), symbol: "folder", documents: sortedForStack(uncategorized)))
        }
        return groups
    }

    /// Favorites sit at the front (bottom) of each stack, fully visible.
    private func sortedForStack(_ documents: [VaultDocument]) -> [VaultDocument] {
        documents.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return !lhs.isFavorite }
            return lhs.sortKey < rhs.sortKey
        }
    }
}

private struct PersonCardSection: View {
    let section: DocumentsView.PersonSectionModel
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AvatarView(person: section.person, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.person?.displayName ?? String(localized: "Unassigned"))
                        .font(.title3.bold())
                    Text("^[\(section.count) document](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(section.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Label(group.name, systemImage: group.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    CardStack(documents: group.documents, namespace: namespace)
                }
            }
        }
    }
}

/// One Wallet-style stack. Every card links to its detail with a zoom
/// transition that grows the card into the full document.
struct CardStack: View {
    let documents: [VaultDocument]
    let namespace: Namespace.ID
    @ScaledMetric(relativeTo: .title3) private var peek: CGFloat = 66

    var body: some View {
        WalletStackLayout(peek: peek) {
            ForEach(documents) { document in
                NavigationLink(value: document.id) {
                    DocumentCardView(document: document, showsDetails: true)
                }
                .buttonStyle(CardPressStyle())
                .matchedTransitionSource(id: document.id, in: namespace) { source in
                    source.clipShape(.rect(cornerRadius: DocumentCardView.cornerRadius, style: .continuous))
                }
            }
        }
    }
}

/// A subtle press-down effect for cards, like Wallet.
struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

private struct EmptyDocumentsView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("No Documents", systemImage: "wallet.pass")
        } description: {
            Text("Scan your passport, license or insurance card. Everything stays encrypted on this iPhone.")
        } actions: {
            Button {
                router.addSource = .scan
            } label: {
                Label("Scan Document", systemImage: "doc.viewfinder")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button("Enter Manually") {
                router.addSource = .manual
            }
            .buttonStyle(.glass)
        }
    }
}

/// Looks up a document for navigation, with an empty state if it was deleted.
struct DocumentDetailLoader: View {
    let id: UUID
    @Query private var matches: [VaultDocument]

    init(id: UUID) {
        self.id = id
        _matches = Query(filter: #Predicate<VaultDocument> { $0.id == id })
    }

    var body: some View {
        if let document = matches.first {
            DocumentDetailView(document: document)
        } else {
            ContentUnavailableView("Document Not Found", systemImage: "doc.questionmark", description: Text("It may have been deleted."))
        }
    }
}
