import LocalAuthentication
import os
import SwiftUI

/// Face ID / Touch ID / passcode lock for the whole app.
///
/// Vault starts locked, and locks again after it has been in the background
/// for the auto-lock interval. Revealing a sensitive number or opening a
/// document from Siri, a widget, Control Center or Spotlight always asks again.
@MainActor @Observable
final class AppLock {
    enum Timeout: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300

        var id: Int { rawValue }

        var name: String {
            switch self {
            case .immediately: String(localized: "Immediately")
            case .oneMinute: String(localized: "After 1 Minute")
            case .fiveMinutes: String(localized: "After 5 Minutes")
            }
        }
    }

    private(set) var isLocked = true
    private(set) var isAuthenticating = false
    private(set) var lastError: String?
    /// Increments on every successful unlock (drives the unlock haptic).
    private(set) var unlockCount = 0
    /// True when the device has no passcode, so Vault can't protect itself.
    private(set) var deviceHasNoPasscode = false

    var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: SettingsKey.lockEnabled) }
    }

    var timeout: Timeout {
        didSet { UserDefaults.standard.set(timeout.rawValue, forKey: SettingsKey.autoLock) }
    }

    /// Called whenever Vault locks, so decrypted data can be dropped from memory.
    var onLock: (() -> Void)?

    private var backgroundedAt: Date?
    /// Face ID is offered automatically once at launch and once per return
    /// from the background, never in a loop after the person cancels.
    private var autoPromptPending = true
    private let logger = Logger(subsystem: "app.vault", category: "lock")

    init() {
        let defaults = UserDefaults.standard
        lockEnabled = defaults.object(forKey: SettingsKey.lockEnabled) as? Bool ?? true
        timeout = Timeout(rawValue: defaults.integer(forKey: SettingsKey.autoLock)) ?? .immediately
        isLocked = lockEnabled
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        default: String(localized: "Passcode")
        }
    }

    var biometrySymbol: String {
        switch biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    // MARK: Lock and unlock

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: String(localized: "Unlock your documents")) {
            isLocked = false
            unlockCount += 1
        }
    }

    func lock() {
        guard lockEnabled else { return }
        isLocked = true
        onLock?()
    }

    /// Forces Face ID before a document opened from outside the app (Siri,
    /// widgets, Control Center, Spotlight, Quick Actions) is shown.
    func requireFreshAuthentication() {
        guard lockEnabled else { return }
        isLocked = true
        autoPromptPending = true
    }

    func consumeAutoPrompt() -> Bool {
        guard autoPromptPending, isLocked else { return false }
        autoPromptPending = false
        return true
    }

    func sceneDidEnterBackground() {
        backgroundedAt = .now
        autoPromptPending = true
        if timeout == .immediately { lock() }
    }

    func sceneWillEnterForeground() {
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return }
        if Date.now.timeIntervalSince(backgroundedAt) >= TimeInterval(timeout.rawValue) {
            lock()
        }
    }

    // MARK: Authentication

    /// Asks for Face ID, Touch ID or the device passcode.
    func authenticate(reason: String) async -> Bool {
        guard lockEnabled else { return true }
        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil

        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use Passcode")
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            if let error = policyError, LAError.Code(rawValue: error.code) == .passcodeNotSet {
                // Without a device passcode there is nothing to authenticate
                // against (this is also the Simulator's default). Let the person
                // in, and show a warning in Settings.
                deviceHasNoPasscode = true
                return true
            }
            lastError = policyError?.localizedDescription
            return false
        }
        deviceHasNoPasscode = false

        let result: (Bool, LAError.Code?) = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { @Sendable success, error in
                continuation.resume(returning: (success, (error as? LAError)?.code))
            }
        }
        if !result.0 {
            switch result.1 {
            case .userCancel?, .systemCancel?, .appCancel?: break
            case let code?: lastError = Self.message(for: code)
            case nil: break
            }
            logger.info("Authentication did not succeed")
        }
        return result.0
    }

    private static func message(for code: LAError.Code) -> String {
        switch code {
        case .biometryLockout: String(localized: "Face ID is locked. Use your passcode to unlock.")
        case .biometryNotEnrolled: String(localized: "Set up Face ID in Settings, or use your passcode.")
        case .authenticationFailed: String(localized: "Authentication failed. Try again.")
        default: String(localized: "Vault couldn’t be unlocked. Try again.")
        }
    }
}
