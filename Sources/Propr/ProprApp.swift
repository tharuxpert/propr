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
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

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

    @objc private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.showSettingsWindow()
        }
    }

    @MainActor
    private func showSettingsWindow() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())

            // Tell the hosting controller to let Auto Layout fully control its size.
            hostingController.sizingOptions = []

            // Wider initial + minimum size to accommodate the new left sidebar + content.
            let contentRect = NSRect(x: 0, y: 0, width: 760, height: 620)
            let window = NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            let hostingView = hostingController.view
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            window.contentView = hostingView
            window.title = "Settings"
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.center()
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.minSize = NSSize(width: 680, height: 540)
            // Do not use .canJoinAllSpaces — we want the settings window to stay on the current Space
            // like a normal utility window, not follow the user across all desktops.
            window.collectionBehavior = []

            // Pin the hosting view to all edges
            if let contentView = window.contentView {
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Force layout so the hosted SwiftUI content gets its size immediately
        settingsWindow?.contentView?.layoutSubtreeIfNeeded()
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

    /// Called from the menu when the user explicitly chooses "Permissions & Setup...".
    /// We show the onboarding UI (it handles both first-run and returning users with missing permission).
    @MainActor
    func showOnboardingForPermissionRecovery() {
        // Reset the launch guard so an explicit menu action can show it even on the same launch.
        accessibility.resetOnboardingAttemptFlag()
        showOnboardingWindow()
    }

    @MainActor
    private func showOnboardingIfNeededOnLaunch() {
        // Quick permission check using the main manager
        accessibility.checkPermission(prompt: false)

        // Show the onboarding/permission window on launch if permission is missing.
        // This applies to both true first runs and returning users whose permission
        // became unavailable (new build, TCC reset, etc.).
        //
        // The hasAttempted guard + final delayed re-check prevents most transient
        // false positives. The header inside OnboardingView is toned down for
        // returning users so it doesn't feel like marketing spam.
        guard !accessibility.hasPermission else { return }

        guard !accessibility.hasAttemptedAutoShowOnboardingThisLaunch else { return }
        accessibility.markAutoShowOnboardingAttempted()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Final defensive check right before showing (gives monitoring / TCC more time)
                self.accessibility.checkPermission(prompt: false)
                if !self.accessibility.hasPermission {
                    self.showOnboardingWindow()
                }
            }
        }
    }

    // MARK: - Manual window presentation (reliable for LSUIElement + menu triggers)

    @MainActor
    private func showOnboardingWindow() {
        if onboardingWindow == nil {
            let hosting = NSHostingView(rootView: OnboardingView(
                accessibility: accessibility,
                onComplete: { [weak self] in
                    // OnboardingView already set the UserDefaults flag inside completeOnboarding()
                    self?.onboardingWindow?.orderOut(nil)

                    // Belt-and-suspenders: make sure the permissions menu item is gone
                    // if this completion path is taken after granting.
                    StatusItemController.shared.refreshMenu()
                },
                onPermissionGranted: { [weak self] in
                    self?.onboardingWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    // Make the menu item disappear promptly when they grant from System Settings.
                    StatusItemController.shared.refreshMenu()
                }
            ))

            let contentRect = NSRect(x: 0, y: 0, width: 460, height: 540)
            hosting.frame = contentRect

            let window = NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Propr"
            window.identifier = NSUserInterfaceItemIdentifier("onboarding")
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            onboardingWindow = window
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


}

// Full AppKit status item for reliable menubar menu (no SwiftUI hover flicker).
// This gives native macOS menu behavior including proper hover highlighting on submenus.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    private var permissionCancellable: AnyCancellable?
    private var modelChangeObserver: NSObjectProtocol?
    
    private override init() {
        super.init()
    }
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
        }
        
        let menu = buildMainMenu()
        menu.delegate = self
        statusItem?.menu = menu

        // Live update the menu when permission state changes (so "Permissions & Setup..."
        // disappears immediately after the user grants it, without needing to re-open the menu).
        permissionCancellable = AccessibilityManager.shared.$hasPermission
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }

        modelChangeObserver = NotificationCenter.default.addObserver(
            forName: .proprModelStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenu()
            }
        }
    }
    
    /// Forces a fresh permission check + rebuild of the dynamic parts of the menu.
    /// Safe to call from anywhere (e.g. when permission is granted from the onboarding window).
    func refreshMenu() {
        AccessibilityManager.shared.checkPermission(prompt: false)

        let freshMenu = buildMainMenu()
        freshMenu.delegate = self
        statusItem?.menu = freshMenu
    }
    
    private func buildMainMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Show Floating Bar
        let showBar = NSMenuItem(title: "Show Floating Bar", action: #selector(showFloatingBar), keyEquivalent: "")
        showBar.target = self
        menu.addItem(showBar)
        
        menu.addItem(.separator())
        
        // Model submenu (dynamic)
        let modelMenu = buildModelSubmenu()
        let modelItem = NSMenuItem(title: "Model...", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        
        menu.addItem(.separator())
        
        // Settings
        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        
        // Permissions & Setup (only when accessibility is missing)
        // This keeps the menu in sync with reality so users don't get surprised by the
        // onboarding window on launch when permissions are actually fine.
        if !AccessibilityManager.shared.hasPermission {
            let perms = NSMenuItem(title: "Permissions & Setup...", action: #selector(openPermissions), keyEquivalent: "")
            perms.target = self
            if let icon = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: "Permissions") {
                icon.isTemplate = true
                perms.image = icon
            }
            menu.addItem(perms)
        }
        
        menu.addItem(.separator())
        
        // Quit
        let quit = NSMenuItem(title: "Quit Propr", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        if let icon = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit") {
            icon.isTemplate = true
            quit.image = icon
        }
        menu.addItem(quit)
        
        return menu
    }
    
    private func buildModelSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        
        let models = ModelStore.shared.allAvailableModels
        
        if models.isEmpty {
            let item = NSMenuItem(title: "No models configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for model in models {
                let item = NSMenuItem(title: model.displayName, action: #selector(selectModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.id.uuidString
                
                if model.id == ModelStore.shared.selectedModelID {
                    item.state = .on
                }
                
                submenu.addItem(item)
            }
        }
        
        submenu.addItem(.separator())
        
        let manage = NSMenuItem(title: "Manage Models...", action: #selector(openManageModels), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
        
        return submenu
    }
    
    // Called by the system right before the menu is shown.
    func menuWillOpen(_ menu: NSMenu) {
        // Make sure everything (permission item + model checkmark) is up to date.
        refreshMenu()
    }
    
    @objc private func showFloatingBar() {
        NotificationCenter.default.post(name: AppDelegate.summonFloatingBarNotification, object: nil)
    }
    
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString),
              let model = ModelStore.shared.allAvailableModels.first(where: { $0.id == uuid }) else { return }
        
        ModelStore.shared.selectModel(model)
    }
    
    @objc private func openSettings() {
        NotificationCenter.default.post(name: .proprOpenSettings, object: nil)
    }

    @objc private func openManageModels() {
        NotificationCenter.default.post(
            name: .proprOpenSettings,
            object: nil,
            userInfo: ["selectSection": "models"]
        )
    }
    
    @objc private func openPermissions() {
        // For returning users we still want the real OnboardingView (it handles the
        // current permission state + "Start using Propr" button gracefully).
        AppDelegate.shared?.showOnboardingForPermissionRecovery()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
