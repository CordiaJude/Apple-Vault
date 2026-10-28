import SwiftUI

/// The document's card at the top of its detail page. Shows the scanned front
/// (or the designed card if there is no scan) and flips to the back with a tap.
struct CardHeroView: View {
    let document: VaultDocument
    var maxHeight: CGFloat = 300

    @State private var isFlipped = false
    @State private var front: UIImage?
    @State private var back: UIImage?
    @State private var flipCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canFlip: Bool { back != nil }

    var body: some View {
        FlippableCard(isFlipped: isFlipped, reduceMotion: reduceMotion) {
            face(front)
        } back: {
            face(back)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .padding(.horizontal, 20)
        .contentShape(.rect)
        .onTapGesture {
            guard canFlip else { return }
            flip()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFlipped ? Text("Back of \(document.title)") : Text("Front of \(document.title)"))
        .accessibilityAddTraits(.isImage)
        .accessibilityActions {
            if canFlip {
                Button("Flip Card") { flip() }
            }
        }
        .task(id: document.updatedAt) {
            front = document.frontPage?.image()
            back = document.backPage?.image()
        }
    }

    private func flip() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2)) {
            isFlipped.toggle()
        }
        flipCount += 1
    }

    @ViewBuilder
    private func face(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        } else {
            DocumentCardView(document: document)
        }
    }
}

/// Two faces with a 3D flip (or a cross-fade with Reduce Motion).
struct FlippableCard<Front: View, Back: View>: View {
    let isFlipped: Bool
    let reduceMotion: Bool
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    var body: some View {
        ZStack {
            front
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (isFlipped ? 180 : 0)), axis: (0, 1, 0), perspective: 0.5)
            back
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (isFlipped ? 0 : -180)), axis: (0, 1, 0), perspective: 0.5)
        }
    }
}
