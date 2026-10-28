import SwiftUI

/// A person's avatar: their photo, a Memoji-style emoji, or their initials on
/// their color.
struct AvatarView: View {
    var color: CardColor
    var emoji: String
    var initials: String
    var photo: UIImage?
    var size: CGFloat

    init(person: Person?, size: CGFloat = 40) {
        color = person?.color ?? .graphite
        emoji = person?.emoji ?? ""
        initials = person?.initials ?? ""
        photo = person?.photo
        self.size = size
    }

    init(color: CardColor, emoji: String, initials: String, photo: UIImage?, size: CGFloat) {
        self.color = color
        self.emoji = emoji
        self.initials = initials
        self.photo = photo
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.circle)
            } else if !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.56))
            } else if !initials.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
