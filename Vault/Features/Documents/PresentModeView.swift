import SwiftUI
import UIKit

/// Full-screen "Present" mode for showing an ID or insurance card at a
/// counter: maximum brightness, the screen stays awake, tap to flip.
struct PresentModeView: View {
    let document: VaultDocument

    @Environment(\.dismiss) private var dismiss
    @Environment(ScreenCaptureMonitor.self) private var captureMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var front: UIImage?
    @State private var back: UIImage?
    @State private var isFlipped = false
    @State private var flipCount = 0
    @State private var savedBrightness: CGFloat?
    @State private var isLandscape = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if captureMonitor.isCaptured {
                CaptureBlockedView()
                    .environment(\.colorScheme, .dark)
            } else {
                card
                    .padding(24)
                    .rotationEffect(.degrees(isLandscape ? 90 : 0))
                    .scaleEffect(isLandscape ? 1.45 : 1)
                    .animation(reduceMotion ? nil : .spring(duration: 0.5), value: isLandscape)
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { hint }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.impact(weight: .light), trigger: flipCount)
        .task {
            front = document.frontPage?.image()
            back = document.backPage?.image()
        }
        .onAppear { brighten() }
        .onDisappear { restore() }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? brighten() : restore()
        }
    }

    private var card: some View {
        FlippableCard(isFlipped: isFlipped, reduceMotion: reduceMotion) {
            face(front)
        } back: {
            face(back)
        }
        .contentShape(.rect)
        .onTapGesture {
            guard back != nil else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2)) {
                isFlipped.toggle()
            }
            flipCount += 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFlipped ? Text("Back of \(document.title)") : Text("Front of \(document.title)"))
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private func face(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
        } else {
            DocumentCardView(document: document)
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Done")

                Spacer()

                Text(document.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    isLandscape.toggle()
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(isLandscape ? "Show Upright" : "Show Sideways")
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if back != nil && !captureMonitor.isCaptured {
            Label(isFlipped ? "Tap to show front" : "Tap to show back", systemImage: "hand.tap")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
                .accessibilityHidden(true)
        }
    }

    // MARK: Brightness and idle timer

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    private func brighten() {
        UIApplication.shared.isIdleTimerDisabled = true
        guard let screen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = 1
    }

    private func restore() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let savedBrightness, let screen {
            screen.brightness = savedBrightness
        }
        savedBrightness = nil
    }
}
