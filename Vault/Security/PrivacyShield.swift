import SwiftUI
import UIKit

/// Watches for screen recording, AirPlay mirroring and other capture of the
/// screen, so Vault can hide documents while it is active.
@MainActor @Observable
final class ScreenCaptureMonitor {
    private(set) var isCaptured = false

    fileprivate func update(_ captured: Bool) {
        if captured != isCaptured { isCaptured = captured }
    }
}

/// An invisible view that reports the window scene's capture state using the
/// `sceneCaptureState` trait.
struct ScreenCaptureObserver: UIViewRepresentable {
    let monitor: ScreenCaptureMonitor

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.monitor = monitor
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {}

    final class ObserverView: UIView {
        weak var monitor: ScreenCaptureMonitor?

        override init(frame: CGRect) {
            super.init(frame: frame)
            registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: ObserverView, _: UITraitCollection) in
                view.report()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            monitor?.update(traitCollection.sceneCaptureState == .active)
        }
    }
}

/// Covers the app in the App Switcher and whenever Vault is not frontmost.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                Text("Vault")
                    .font(.title2.bold())
            }
            .accessibilityElement(children: .combine)
        }
        .ignoresSafeArea()
    }
}

/// Shown over document content while the screen is being recorded or mirrored.
struct CaptureBlockedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Hidden While Recording", systemImage: "record.circle")
        } description: {
            Text("Vault hides your documents while your screen is being recorded or mirrored.")
        }
    }
}

extension View {
    /// Hides this view's content while the screen is captured.
    func hiddenWhileCaptured(_ monitor: ScreenCaptureMonitor) -> some View {
        modifier(CaptureHidingModifier(monitor: monitor))
    }
}

private struct CaptureHidingModifier: ViewModifier {
    let monitor: ScreenCaptureMonitor

    func body(content: Content) -> some View {
        content
            .opacity(monitor.isCaptured ? 0 : 1)
            .overlay {
                if monitor.isCaptured {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary, in: .rect(cornerRadius: 12))
                        .accessibilityLabel("Hidden while recording")
                }
            }
    }
}
