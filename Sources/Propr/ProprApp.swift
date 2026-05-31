import SwiftUI
import AppKit
@preconcurrency import ApplicationServices
import Combine

// Custom notification so the AppDelegate can reliably tell the SwiftUI side to show onboarding
extension Notification.Name {
    static let proprDidFinishLaunching = Notification.Name("proprDidFinishLaunching")
}

@main
struct ProprApp: App {
    // Access the single long-lived instances that live on the AppDelegate.
    // This avoids duplicate managers/detectors in a menu-bar-only LSUIElement app.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var accessibility: AccessibilityManager { appDelegate.accessibility }
    private var fieldDetector: FocusedFieldDetector { appDelegate.fieldDetector }

    init() {
        // Nothing extra — the delegate wires everything in applicationDidFinishLaunching.
    }

    var body: some Scene {
        // Menu bar only. No Dock icon (controlled via Info.plist LSUIElement).
        MenuBarExtra {
            MenuBarContent(accessibility: appDelegate.accessibility)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)

        // Onboarding / permission setup window
        Window("Welcome to Propr", id: "onboarding") {
            OnboardingView(accessibility: appDelegate.accessibility)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Settings window (placeholder for now)
        Window("Propr Settings", id: "settings") {
            SettingsPlaceholderView()
                .frame(width: 420, height: 280)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// The actual menu content as a proper View so @Environment values (especially openWindow) resolve correctly.
struct MenuBarContent: View {
    @ObservedObject var accessibility: AccessibilityManager
    @Environment(\.openWindow) private var openWindow

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        // Backup trigger from AppDelegate
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .proprDidFinishLaunching)) { _ in
                attemptToShowOnboarding(reason: "notification")
            }

        // Force a fresh check every time the user opens the menu so the
        // "Permissions & Setup..." item disappears immediately after granting.
        Color.clear
            .onAppear {
                accessibility.checkPermission(prompt: false)
            }

        Button {
            openWindow(id: "settings")
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        if accessibility.hasPermission {
            Button {
                // Manual summon is useful when auto-detection is noisy or the user wants explicit control.
                (NSApp.delegate as? AppDelegate)?.summonFloatingBar()
            } label: {
                Label("Refine focused field", systemImage: "sparkles")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        } else {
            Button {
                openWindow(id: "onboarding")
            } label: {
                Label("Permissions & Setup...", systemImage: "exclamationmark.shield")
            }
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Propr", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func attemptToShowOnboarding(reason: String) {
        guard !hasCompletedOnboarding || !accessibility.hasPermission else { return }

        // Prevent duplicate onboarding windows.
        // The AppDelegate cold-launch path (manual NSPanel) + this flag ensure we only try once per run.
        guard !accessibility.hasAttemptedAutoShowOnboardingThisLaunch else { return }
        accessibility.markAutoShowOnboardingAttempted()

        // Single delayed attempt is sufficient for the menu backup paths.
        // The main reliable cold-launch show now happens directly from AppDelegate via NSPanel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !hasCompletedOnboarding || !accessibility.hasPermission else { return }

            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - App Delegate (gives us the most reliable "app finished launching" hook)
// Marked @MainActor because it owns @MainActor-isolated objects (AccessibilityManager, detector, controller)
// and all delegate callbacks + AX work happen on the main thread anyway.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// We keep a reference to the onboarding panel so we can close it from the SwiftUI side.
    private var onboardingPanel: NSPanel?

    // Long-lived core objects owned by the delegate (reliable lifetime in LSUIElement apps).
    let accessibility = AccessibilityManager()
    let fieldDetector = FocusedFieldDetector()
    // Eagerly created so its Combine subscription to the detector is active for the entire lifetime.
    // This is what actually drives the auto-show behavior when a text field is focused.
    private let floatingBarController: FloatingBarController

    private var permissionCancellable: AnyCancellable?

    override init() {
        // Must create the controller *after* fieldDetector so we can pass it.
        // This ensures the observation that drives auto-show is wired from the very beginning.
        floatingBarController = FloatingBarController(detector: fieldDetector)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire permission → detector start (single source of truth in the delegate)
        permissionCancellable = accessibility.$hasPermission
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in
                guard let self else { return }
                if granted {
                    print("[Propr] Accessibility permission is now true — starting focus detector")
                    self.fieldDetector.start()
                } else {
                    print("[Propr] Accessibility permission lost — stopping focus detector")
                    self.fieldDetector.stop()
                }
            }

        // Kick an initial permission check
        accessibility.startMonitoring()
        accessibility.checkPermission(prompt: false)

        // This is the most reliable place to decide to show onboarding on a true cold launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                self?.showOnboardingIfNeededOnLaunch()
            }
        }
    }

    /// Called from the menu bar ("Refine focused field" or ⌘⇧R).
    @MainActor
    func summonFloatingBar() {
        floatingBarController.summonForCurrentFocus()
    }

    @MainActor
    private func showOnboardingIfNeededOnLaunch() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Quick permission check (we don't want to show the window if they already granted it before)
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)

        guard !hasCompleted || !hasPermission else { return }

        // Use the delegate-owned manager so monitoring state stays consistent
        let manager = self.accessibility

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false          // Keep the panel visible even when user switches to System Settings
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let contentView = OnboardingView(
            accessibility: manager,
            onComplete: {
                // Close action for when the user taps "Start using Propr"
                panel.orderOut(nil)
                panel.close()
            },
            onPermissionGranted: {
                // Bring the panel back to front when we detect the permission was just granted
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 460, height: 540)
        panel.contentView = hostingView
        panel.center()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.onboardingPanel = panel
    }
}

// Temporary placeholder so the Settings button does something visible.
// This whole view + window will be replaced with real settings on a later branch.
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text("Propr Settings")
                .font(.title2.weight(.semibold))

            Text("This is just a placeholder.\nReal settings (API keys, always-approve toggle, launch at login, etc.) will be built on a dedicated branch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()

            Text("v0.1.0  •  menu bar only  •  native Swift")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Required for windows opened from menu-bar-only apps (LSUIElement)
            // so the window actually appears in front and can receive focus.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
