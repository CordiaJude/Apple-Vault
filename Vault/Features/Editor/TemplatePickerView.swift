import SwiftUI

/// Choose a document type, grouped like the categories on the Documents tab.
struct TemplatePickerView: View {
    var selection: DocumentKind?
    var onSelect: (DocumentKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(BuiltInCategory.allCases, id: \.self) { category in
                    let kinds = DocumentKind.allCases.filter { $0.category == category && matches($0) }
                    if !kinds.isEmpty {
                        Section(category.name) {
                            ForEach(kinds) { kind in
                                Button {
                                    onSelect(kind)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        DocumentGlyph(kind: kind, color: kind.defaultColor)
                                        Text(kind.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if kind == selection {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .accessibilityAddTraits(kind == selection ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Document Types")
            .navigationTitle("Document Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func matches(_ kind: DocumentKind) -> Bool {
        query.isEmpty || kind.name.localizedStandardContains(query)
    }
}
