import SwiftData
import SwiftUI

/// Everything that expires, soonest first, in sections like Calendar's
/// upcoming list.
struct ExpiringView: View {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<VaultDocument> { $0.expiresOn != nil }, sort: \VaultDocument.expiresOn)
    private var documents: [VaultDocument]

    enum Bucket: Int, CaseIterable, Identifiable {
        case expired, next30Days, next6Months, later

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .expired: String(localized: "Expired")
            case .next30Days: String(localized: "Next 30 Days")
            case .next6Months: String(localized: "Next 6 Months")
            case .later: String(localized: "Later")
            }
        }

        init(_ status: ExpiryStatus) {
            switch status {
            case .expired: self = .expired
            case .soon: self = .next30Days
            case .upcoming: self = .next6Months
            default: self = .later
            }
        }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.expiringPath) {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Expiring", systemImage: "calendar.badge.checkmark")
                    } description: {
                        Text("Documents with an expiration date appear here, with reminders before they expire.")
                    }
                } else {
                    List {
                        ForEach(Bucket.allCases) { bucket in
                            let items = documents.filter { Bucket($0.expiryStatus) == bucket }
                            if !items.isEmpty {
                                Section {
                                    ForEach(bucket == .expired ? items.reversed() : items) { document in
                                        NavigationLink(value: document.id) {
                                            ExpiringRow(document: document)
                                        }
                                    }
                                } header: {
                                    Text(bucket.title)
                                        .foregroundStyle(bucket == .expired ? .red : .secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Expiring")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                DocumentDetailLoader(id: id)
            }
        }
    }
}

struct ExpiringRow: View {
    let document: VaultDocument

    var body: some View {
        HStack(spacing: 14) {
            DocumentGlyph(kind: document.kind, color: document.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let person = document.person {
                        Text(person.displayName)
                        Text("·")
                    }
                    if let expiry = document.expiresOn {
                        Text(expiry.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let expiry = document.expiresOn {
                ExpiryBadge(date: expiry)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A small rounded square with the document kind's symbol on its card color,
/// like the app icons in Settings.
struct DocumentGlyph: View {
    let kind: DocumentKind
    let color: CardColor
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color.prefersDarkForeground ? .black.opacity(0.8) : .white)
            }
            .accessibilityHidden(true)
    }
}
