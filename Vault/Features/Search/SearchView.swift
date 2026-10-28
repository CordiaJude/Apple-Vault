import SwiftData
import SwiftUI

/// The search tab. Searches titles, people, tags, typed fields and the text
/// recognized from scans, all on device.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \VaultDocument.title) private var documents: [VaultDocument]
    @Query(sort: \DocumentCategory.sortOrder) private var categories: [DocumentCategory]

    @State private var query = ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Identifiable {
        case all, titles, fields, text
        var id: String { rawValue }

        var name: String {
            switch self {
            case .all: String(localized: "All")
            case .titles: String(localized: "Titles")
            case .fields: String(localized: "Fields")
            case .text: String(localized: "Scanned Text")
            }
        }
    }

    struct Result: Identifiable {
        var document: VaultDocument
        var match: String?
        var id: UUID { document.id }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.searchPath) {
            Group {
                if trimmedQuery.isEmpty {
                    browse
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else {
                    List(results) { result in
                        NavigationLink(value: result.document.id) {
                            SearchResultRow(result: result)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Documents, numbers, text")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.name).tag(scope)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                DocumentDetailLoader(id: id)
            }
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var browse: some View {
        if documents.isEmpty {
            ContentUnavailableView("Nothing to Search", systemImage: "magnifyingglass", description: Text("Documents you add will be searchable here, including the text in your scans."))
        } else {
            List {
                Section("Browse") {
                    ForEach(categories.filter { !($0.documents ?? []).isEmpty }) { category in
                        Button {
                            query = category.name
                            scope = .all
                        } label: {
                            LabeledContent {
                                Text("\(category.documents?.count ?? 0)")
                            } label: {
                                Label(category.name, systemImage: category.symbol)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Recently Edited") {
                    ForEach(documents.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)) { document in
                        NavigationLink(value: document.id) {
                            SearchResultRow(result: Result(document: document))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var results: [Result] {
        let q = trimmedQuery
        return documents.compactMap { document in
            if scope == .all || scope == .titles {
                if document.title.localizedStandardContains(q)
                    || document.kind.name.localizedStandardContains(q)
                    || (document.person?.displayName.localizedStandardContains(q) ?? false)
                    || (document.category?.name.localizedStandardContains(q) ?? false)
                    || document.tags.contains(where: { $0.localizedStandardContains(q) }) {
                    return Result(document: document)
                }
            }
            guard scope != .titles else { return nil }
            let payload = document.payload
            if scope == .all || scope == .fields {
                if let field = payload.fields.first(where: { $0.value.localizedStandardContains(q) || $0.label.localizedStandardContains(q) }) {
                    let value = field.isSensitive ? field.maskedValue : field.displayValue
                    return Result(document: document, match: "\(field.label): \(value)")
                }
                if payload.notes.localizedStandardContains(q) {
                    return Result(document: document, match: snippet(payload.notes, around: q))
                }
            }
            if scope == .all || scope == .text, payload.recognizedText.localizedStandardContains(q) {
                return Result(document: document, match: snippet(payload.recognizedText, around: q))
            }
            return nil
        }
    }

    private func snippet(_ text: String, around query: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flattened.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flattened.prefix(80))
        }
        let start = flattened.index(range.lowerBound, offsetBy: -30, limitedBy: flattened.startIndex) ?? flattened.startIndex
        let end = flattened.index(range.upperBound, offsetBy: 50, limitedBy: flattened.endIndex) ?? flattened.endIndex
        return (start > flattened.startIndex ? "…" : "") + flattened[start..<end] + (end < flattened.endIndex ? "…" : "")
    }
}

private struct SearchResultRow: View {
    let result: SearchView.Result

    var body: some View {
        HStack(spacing: 14) {
            DocumentGlyph(kind: result.document.kind, color: result.document.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.document.title)
                    .font(.body.weight(.medium))
                Text(result.match ?? [result.document.person?.displayName, result.document.kind.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
