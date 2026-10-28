import SwiftUI

/// A document drawn the way Wallet draws a pass: a solid, colorful card with
/// depth. Cards are content, so they never use glass.
struct DocumentCardView: View {
    let document: VaultDocument
    var showsDetails = true

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let aspectRatio: CGFloat = 1.586
    static let cornerRadius: CGFloat = 20

    var body: some View {
        CardFace(
            title: document.title,
            kind: document.kind,
            color: document.color,
            holder: document.person?.displayName,
            expiresOn: document.expiresOn,
            isFavorite: document.isFavorite,
            showsDetails: showsDetails
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [document.title, document.kind.name]
        if let person = document.person { parts.append(person.displayName) }
        if document.expiresOn != nil { parts.append(document.subtitle) }
        if document.isFavorite { parts.append(String(localized: "Favorite")) }
        return parts.joined(separator: ", ")
    }
}

/// The visual card, independent of the model so it can also render sample
/// images, previews and empty templates.
struct CardFace: View {
    var title: String
    var kind: DocumentKind
    var color: CardColor
    var holder: String?
    var expiresOn: Date?
    var isFavorite = false
    var showsDetails = true

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var foreground: Color { color.prefersDarkForeground ? .black.opacity(0.85) : .white }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DocumentCardView.cornerRadius, style: .continuous) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(color.gradient)

            // A large, faint emblem, like the artwork on a Wallet pass.
            Image(systemName: kind.symbol)
                .font(.system(size: 150, weight: .bold))
                .foregroundStyle(foreground.opacity(0.10))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 30, y: 36)
                .accessibilityHidden(true)

            // Soft top sheen for depth.
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                .clipShape(shape)
                .blendMode(.softLight)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Label(kind.name.uppercased(), systemImage: kind.symbol)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .opacity(0.85)
                    Spacer(minLength: 8)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    if let badge {
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badge.color, in: .capsule)
                            .foregroundStyle(.white)
                    }
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.8)

                if showsDetails {
                    Spacer(minLength: 12)
                    HStack(alignment: .bottom) {
                        if let holder {
                            detail(String(localized: "HOLDER"), holder)
                        }
                        Spacer(minLength: 12)
                        if let expiresOn {
                            detail(String(localized: "EXPIRES"), expiresOn.formatted(.dateTime.month(.abbreviated).day().year()), alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .foregroundStyle(foreground)
        }
        .aspectRatio(dynamicTypeSize.isAccessibilitySize ? nil : DocumentCardView.aspectRatio, contentMode: .fit)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 220 : nil)
        .overlay(shape.strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.18), lineWidth: contrast == .increased ? 1.5 : 0.75))
        .compositingGroup()
        .shadow(color: color.bottomColor.opacity(0.35), radius: 10, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private func detail(_ label: String, _ value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .opacity(0.7)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var badge: (text: String, color: Color)? {
        switch ExpiryStatus(expiresOn: expiresOn) {
        case .expired: (String(localized: "Expired"), .red)
        case .soon: (String(localized: "Expiring"), .orange)
        default: nil
        }
    }
}

/// Lays cards out like Wallet: each card overlaps the one before it, leaving
/// its top edge visible; the last card is shown in full.
struct WalletStackLayout: Layout {
    var peek: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        guard let last = subviews.last else { return .zero }
        let lastHeight = last.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: CGFloat(subviews.count - 1) * peek + lastHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index) * peek),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}
