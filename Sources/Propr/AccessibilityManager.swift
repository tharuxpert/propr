import Foundation
@preconcurrency import ApplicationServices
import AppKit

/// Manages Accessibility API permission state for Propr.
/// 
/// - Only reports `hasPermission == true` when the system actually trusts the app (never guesses).
/// - Can request the standard macOS prompt.
/// - Actively monitors for changes (polling + app activation) so the UI updates live
///   when the user toggles permission in System Settings.
@MainActor
final class AccessibilityManager: ObservableObject {
    @Published private(set) var hasPermission: Bool = false
    @Published private(set) var isChecking: Bool = false

    /// Used to prevent multiple auto-show attempts for the onboarding window in one app run.
    @Published private(set) var hasAttemptedAutoShowOnboardingThisLaunch = false

    private var monitoringTask: Task<Void, Never>?
    private var isMonitoring = false
    private var didBecomeActiveObserver: NSObjectProtocol?

    init() {
        // Initial check (fast, no prompt)
        checkPermission(prompt: false)
    }

    /// Performs a fresh check against the system.
    /// - Parameter prompt: If true, macOS will show the standard Accessibility permission prompt.
    func checkPermission(prompt: Bool = false) {
        isChecking = true

        let trusted = checkIsTrusted(prompt: prompt)

        // Only update if it actually changed (keeps UI stable)
        if trusted != hasPermission {
            hasPermission = trusted
        }

        isChecking = false
    }

    /// Opens the Accessibility permission prompt (if not already granted).
    /// This is the official way to trigger the TCC dialog from code.
    func requestPermission() {
        // This call with prompt=true will show the dialog if needed.
        _ = checkIsTrusted(prompt: true)

        // Immediately re-check (the dialog is async; user may take time)
        // Monitoring will catch the real change when they grant it.
        checkPermission(prompt: false)
    }

    /// Starts watching for permission changes while onboarding or settings are visible.
    /// Uses a lightweight timer + listens to app activation.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Listen for when Propr becomes active (user might have switched to System Settings and back)
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission(prompt: false)
            }
        }

        // Poll while the onboarding/settings UI is visible.
        // 900ms is responsive without being wasteful.
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                await MainActor.run {
                    self?.checkPermission(prompt: false)
                }
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil

        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            didBecomeActiveObserver = nil
        }
    }

    /// Marks that we have already attempted to auto-show the onboarding window this launch.
    /// Prevents duplicate windows when menu content re-appears or multiple triggers fire.
    func markAutoShowOnboardingAttempted() {
        hasAttemptedAutoShowOnboardingThisLaunch = true
    }

    /// Opens System Settings directly to the Accessibility privacy pane.
    func openAccessibilitySystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private static let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    private func checkIsTrusted(prompt: Bool) -> Bool {
        let options: [String: Any] = [
            Self.trustedCheckOptionPrompt: prompt
        ]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

