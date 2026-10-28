import SwiftData
import SwiftUI

/// Chooses between the lock screen and the app, and adds the privacy layers
/// that sit above everything: the App Switcher cover, the screen-recording
/// shield and the "Copied" HUD.
struct RootView: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(AppRouter.self) private var router
    @Environment(HUDCenter.self) private var hud
    @Environment(ScreenCaptureMonitor.self) private var captureMonitor
    @Environment(\.scenePhase) private var scenePhase
    @State private var privacyWindow = PrivacyWindow()

    private var privacyContent: PrivacyWindow.Content {
        if lock.isLocked { return .lock }
        return scenePhase == .active ? .hidden : .cover
    }

    var body: some View {
        ZStack {
            switch store.state {
            case .loading:
                ProgressView("Opening Vault…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Vault Couldn’t Open", systemImage: "exclamationmark.lock")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { store.load() }
                        .buttonStyle(.glassProminent)
                }
            case .ready(let container):
                MainTabView()
                    .modelContainer(container)
                    .id(store.generation)
            }

            // Underneath the privacy window, so nothing flashes while it appears.
            if lock.isLocked {
                Rectangle().fill(.background).ignoresSafeArea()
            }
        }
        .overlay { HUDOverlay(center: hud) }
        .background { ScreenCaptureObserver(monitor: captureMonitor).frame(width: 0, height: 0) }
        .sensoryFeedback(.success, trigger: lock.unlockCount)
        .onChange(of: privacyContent, initial: true) { _, content in
            privacyWindow.update(content, lock: lock)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.sceneDidEnterBackground()
            case .active:
                lock.sceneWillEnterForeground()
                InboxImporter.checkForPendingItems(router: router)
            default: break
            }
        }
        .onChange(of: lock.isLocked) { _, isLocked in
            if !isLocked {
                router.performPending(store: store)
                InboxImporter.checkForPendingItems(router: router)
            }
        }
        .onChange(of: ExternalRouteCenter.shared.pending) { _, link in
            guard let link else { return }
            ExternalRouteCenter.shared.pending = nil
            router.handle(link, lock: lock, store: store)
        }
        .task {
            if let link = ExternalRouteCenter.shared.pending {
                ExternalRouteCenter.shared.pending = nil
                router.handle(link, lock: lock, store: store)
            }
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                router.handle(link, lock: lock, store: store)
            }
        }
        .onContinueUserActivity(SpotlightIndexer.activityType) { activity in
            if let id = SpotlightIndexer.documentID(from: activity) {
                router.handle(.document(id), lock: lock, store: store)
            }
        }
    }
}

/// The lock screen. Face ID starts automatically once per return to the app;
/// if it's cancelled, the button tries again.
struct LockView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    private func autoUnlock() async {
        guard scenePhase == .active, lock.consumeAutoPrompt() else { return }
        await lock.unlock()
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: lock.isAuthenticating)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Vault Is Locked")
                        .font(.title2.bold())
                    Text("Your documents are encrypted on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometrySymbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(lock.isAuthenticating)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
        }
        .task { await autoUnlock() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await autoUnlock() } }
        }
    }
}
