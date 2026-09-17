import SwiftUI
import AppKit
@preconcurrency import ApplicationServices
import Combine

extension Notification.Name {
    static let proprOpenSettings = Notification.Name("proprOpenSettings")
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
        // Dummy scene to keep the SwiftUI app lifecycle happy in this LSUIElement app.
        // The actual Settings window is created manually for reliable opening from the menu.
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}

// MARK: - App Delegate (gives us the most reliable "app finished launching" hook)
// Marked @MainActor because it owns @MainActor-isolated objects (AccessibilityManager, detector, controller)
// and all delegate callbacks + AX work happen on the main thread anyway.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Long-lived core objects owned by the delegate (reliable lifetime in LSUIElement apps).
    let accessibility = AccessibilityManager.shared
    let fieldDetector = FocusedFieldDetector()
    // Eagerly created so menu/hotkey summons can reuse one controller for the app lifetime.
    private let floatingBarController: FloatingBarController

    private var permissionCancellable: AnyCancellable?

    // Double-tap Command key detection for quick summon
    private var lastCommandPressTime: Date?
    private var commandKeyMonitor: Any?

    // Lazily-created windows presented manually via NSWindow + NSHostingView.
    // This is required for reliable "Settings..." / "Manage Models..." and first-launch
    // onboarding in a pure LSUIElement (menu-bar-only) agent app.
    // Internal rather than private: AppDelegate+Windows.swift needs them, and
    // Swift's `private` is scoped to the file.
    var onboardingWindow: NSWindow?
    var settingsWindow: NSWindow?

    static let summonFloatingBarNotification = Notification.Name("ProprSummonFloatingBar")

    // Allow the AppKit menu controller to trigger onboarding/permission UI without tight coupling.
    static weak var shared: AppDelegate?

    override init() {
        floatingBarController = FloatingBarController(detector: fieldDetector)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Keep detector state cleared if Accessibility goes away. The floating bar reads focus
        // only when explicitly summoned; it does not run a live focus observer.
        permissionCancellable = accessibility.$hasPermission
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in
                guard let self else { return }
                if !granted {
                    print("[Propr] Accessibility permission lost — stopping focus detector")
                    self.fieldDetector.stop()
                }
            }

        // Kick an initial permission check
        accessibility.startMonitoring()
        accessibility.checkPermission(prompt: false)

        // Double-Command key summon
        setupDoubleCommandHotkey()

        // Reliable way for menu bar items (and anything) to summon the bar
        NotificationCenter.default.addObserver(
            forName: Self.summonFloatingBarNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.summonFloatingBar()
            }
        }

        // Full AppKit status item for reliable menubar (no SwiftUI menu flicker)
        StatusItemController.shared.setup()

        // Listen for requests to open Settings (from AppKit menu items like "Settings..." and "Manage Models...")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .proprOpenSettings,
            object: nil
        )

        // This is the most reliable place to decide to show onboarding on a true cold launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                self?.showOnboardingIfNeededOnLaunch()
            }
        }
    }

    private func setupDoubleCommandHotkey() {
        commandKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }

            let flags = event.modifierFlags

            // Only trigger on *pure* Command (no Shift, Option, Control, etc.)
            // This prevents Command+Shift, Command+Option, etc. from counting as Command presses.
            let isPureCommand = flags.contains(.command) &&
                                !flags.contains(.shift) &&
                                !flags.contains(.option) &&
                                !flags.contains(.control) &&
                                !flags.contains(.function)

            if isPureCommand {
                let now = Date()
                if let last = self.lastCommandPressTime,
                   now.timeIntervalSince(last) < 0.45 {
                    // Double pure Command tap detected
                    self.lastCommandPressTime = nil
                    DispatchQueue.main.async {
                        self.summonFloatingBar()
                    }
                } else {
                    self.lastCommandPressTime = now
                }
            }
        }
    }

    @MainActor
    func summonFloatingBar() {
        floatingBarController.summonForCurrentFocus()
    }
}

