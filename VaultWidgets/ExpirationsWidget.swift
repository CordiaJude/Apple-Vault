import SwiftUI
import WidgetKit

// Widgets show document names and dates only — never numbers or images —
// because they're visible on the Home Screen and Lock Screen.

nonisolated struct ExpirationEntry: TimelineEntry {
    let date: Date
    let items: [VaultSnapshot.Item]
    let isConfigured: Bool

    static let preview = ExpirationEntry(
        date: .now,
        items: [
            .init(id: UUID(), title: "Health Insurance", kind: "healthInsurance", kindName: "Health Insurance", symbol: "cross.case.fill",
                  personName: "Jordan", color: .teal, expiresOn: .now.addingTimeInterval(86_400 * 20), isFavorite: true),
            .init(id: UUID(), title: "Passport", kind: "passport", kindName: "Passport", symbol: "globe.americas.fill",
                  personName: "Jordan", color: .indigo, expiresOn: .now.addingTimeInterval(86_400 * 150), isFavorite: false),
            .init(id: UUID(), title: "Vehicle Registration", kind: "vehicleRegistration", kindName: "Vehicle Registration", symbol: "doc.text.fill",
                  personName: "Jordan", color: .graphite, expiresOn: .now.addingTimeInterval(86_400 * 61), isFavorite: false),
        ],
        isConfigured: true
    )
}

nonisolated struct ExpirationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExpirationEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (ExpirationEntry) -> Void) {
        completion(context.isPreview ? .preview : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpirationEntry>) -> Void) {
        // Refresh just after midnight so "in 3 days" stays correct.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry(at: .now)], policy: .after(tomorrow)))
    }

    private func entry(at date: Date) -> ExpirationEntry {
        let snapshot = VaultSnapshot.load()
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: date) ?? date
        let items = snapshot.expiringItems.filter { ($0.expiresOn ?? .distantPast) >= cutoff }
        return ExpirationEntry(date: date, items: items, isConfigured: AppGroup.isAvailable)
    }
}

/// Home Screen: upcoming expirations.
struct ExpirationsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vault.expirations", provider: ExpirationProvider()) { entry in
            ExpirationsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DeepLink.expiring.url)
        }
        .configurationDisplayName("Upcoming Expirations")
        .description("See which documents expire next. Shows names and dates only.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Lock Screen: the next thing to expire.
struct NextExpiringWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.vault.next", provider: ExpirationProvider()) { entry in
            NextExpiringView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(DeepLink.expiring.url)
        }
        .configurationDisplayName("Next Expiration")
        .description("The next document to expire, on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Views

struct ExpirationsWidgetView: View {
    let entry: ExpirationEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        default: 7
        }
    }

    var body: some View {
        if !entry.isConfigured {
            message("Open Vault", "Widgets need App Groups. See the README.")
        } else if entry.items.isEmpty {
            message("Nothing Expiring", "Documents with expiration dates appear here.")
        } else if family == .systemSmall, let item = entry.items.first {
            small(item)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Expiring", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entry.items.prefix(limit)) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func small(_ item: VaultSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Glyph(item: item, size: 34)
            Spacer(minLength: 0)
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            if let person = item.personName {
                Text(person).font(.caption).foregroundStyle(.secondary)
            }
            if let date = item.expiresOn {
                RelativeExpiry(date: date)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: VaultSnapshot.Item) -> some View {
        HStack(spacing: 10) {
            Glyph(item: item, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if let person = item.personName {
                    Text(person).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let date = item.expiresOn {
                RelativeExpiry(date: date)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func message(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NextExpiringView: View {
    let entry: ExpirationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let item = entry.items.first { ($0.expiresOn ?? .distantPast) >= Calendar.current.startOfDay(for: entry.date) } ?? entry.items.first
        switch family {
        case .accessoryInline:
            if let item, let date = item.expiresOn {
                Label("\(item.title) · \(date.formatted(.dateTime.month(.abbreviated).day()))", systemImage: item.symbol)
            } else {
                Label("Nothing expiring", systemImage: "checkmark.shield")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let item, let date = item.expiresOn {
                    VStack(spacing: 0) {
                        Image(systemName: item.symbol).font(.caption)
                        Text(daysText(date)).font(.headline).minimumScaleFactor(0.6)
                    }
                } else {
                    Image(systemName: "checkmark.shield").font(.title3)
                }
            }
            .widgetAccentable()
        default:
            if let item, let date = item.expiresOn {
                VStack(alignment: .leading, spacing: 1) {
                    Label(item.title, systemImage: item.symbol)
                        .font(.headline)
                        .widgetAccentable()
                    if let person = item.personName {
                        Text(person).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(date < .now ? "Expired \(date.formatted(date: .abbreviated, time: .omitted))" : "Expires \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Nothing expiring soon", systemImage: "checkmark.shield")
            }
        }
    }

    private func daysText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: date).day ?? 0
        if days < 0 { return "!" }
        return days > 99 ? "\(days / 30)mo" : "\(days)d"
    }
}

struct Glyph: View {
    let item: VaultSnapshot.Item
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(renderingMode == .fullColor ? AnyShapeStyle(item.color.gradient) : AnyShapeStyle(.fill.secondary))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: item.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .widgetAccentable()
    }
}

struct RelativeExpiry: View {
    let date: Date

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let days = Calendar.current.dateComponents([.day], from: today, to: date).day ?? 0
        Group {
            if days < 0 {
                Text("Expired").foregroundStyle(.red)
            } else if days == 0 {
                Text("Today").foregroundStyle(.orange)
            } else if days <= 30 {
                Text("\(days) days").foregroundStyle(.orange)
            } else {
                Text(date, format: .dateTime.month(.abbreviated).year())
            }
        }
    }
}

#Preview(as: .systemMedium) {
    ExpirationsWidget()
} timeline: {
    ExpirationEntry.preview
}
