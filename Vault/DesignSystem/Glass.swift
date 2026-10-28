import SwiftUI

// Liquid Glass belongs to the controls layer: floating buttons, toolbars,
// HUDs and sheets. Document cards are content and stay solid.

extension View {
    /// Liquid Glass that falls back to an opaque, high-contrast material when
    /// Reduce Transparency or Increase Contrast is on.
    func vaultGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VaultGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

private struct VaultGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.background.secondary), in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: contrast == .increased ? 1.5 : 0.5))
        } else {
            content
                .glassEffect(glass, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(.primary.opacity(0.35), lineWidth: 1)
                    }
                }
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A transient confirmation ("Copied", "Saved") that floats over content on
/// glass, like the system's own HUDs.
@MainActor @Observable
final class HUDCenter {
    struct Message: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var symbol: String
    }

    private(set) var message: Message?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, symbol: String = "checkmark.circle.fill") {
        message = Message(text: text, symbol: symbol)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            message = nil
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

struct HUDOverlay: View {
    let center: HUDCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let message = center.message {
                Label(message.text, systemImage: message.symbol)
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .vaultGlass(in: .capsule)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(message.id)
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.35), value: center.message)
        .allowsHitTesting(false)
    }
}
