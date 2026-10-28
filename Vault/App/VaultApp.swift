import SwiftData
import SwiftUI

@main
struct VaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VaultStore()
    @State private var lock = AppLock()
    @State private var router = AppRouter()
    @State private var hud = HUDCenter()
    @State private var captureMonitor = ScreenCaptureMonitor()

    init() {
        SecureFiles.clearTemporaryFiles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(router)
                .environment(hud)
                .environment(captureMonitor)
                .onAppear {
                    store.load()
                    lock.onLock = { [store] in
                        store.purgeDecryptedData()
                        VaultCrypto.purgeCachedKey()
                        SecureFiles.clearTemporaryFiles()
                    }
                }
        }
    }
}
