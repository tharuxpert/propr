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
        // Onboarding / permission setup window
        Window("Welcome to Propr", id: "onboarding") {
            OnboardingView(accessibility: appDelegate.accessibility)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Settings window
        Window("Propr Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// The actual menu content as a proper View so @Environment values (especially openWindow) resolve correctly.
struct MenuBarContent: View {
    @ObservedObject var accessibility: AccessibilityManager
    @Environment(\.openWindow) private var openWindow
    @Bindable var modelStore = ModelStore.shared

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

        // Listen for "Manage Models..." request from the isolated ModelSelectionMenu
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .proprOpenSettings)) { _ in
                openWindow(id: "settings")
            }

        // Primary action at the very top, in its own section
        Button {
            NotificationCenter.default.post(name: AppDelegate.summonFloatingBarNotification, object: nil)
        } label: {
            Text("Show Floating Bar")
        }

        Divider()

        // Note: The main menu (including Model selection with native hover/no flicker)
        // is now handled by StatusItemController (AppKit NSStatusItem + NSMenu).
        // We keep minimal SwiftUI items here for the MenuBarExtra icon.

        Button {
            openWindow(id: "settings")
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        if !accessibility.hasPermission {
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
        guard !accessibility.hasAttemptedAutoShowOnboardingThisLaunch else { return }
        accessibility.markAutoShowOnboardingAttempted()

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
    // Long-lived core objects owned by the delegate (reliable lifetime in LSUIElement apps).
    let accessibility = AccessibilityManager()
    let fieldDetector = FocusedFieldDetector()
    // Eagerly created so its Combine subscription to the detector is active for the entire lifetime.
    // This is what actually drives the auto-show behavior when a text field is focused.
    private let floatingBarController: FloatingBarController

    private var permissionCancellable: AnyCancellable?

    // Double-tap Command key detection for quick summon
    private var lastCommandPressTime: Date?
    private var commandKeyMonitor: Any?

    static let summonFloatingBarNotification = Notification.Name("ProprSummonFloatingBar")

    override init() {
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
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Fallback: activate the app so the user can open it manually if needed
            NSApp.activate(ignoringOtherApps: true)
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

    @MainActor
    private func showOnboardingIfNeededOnLaunch() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Quick permission check using the main manager
        accessibility.checkPermission(prompt: false)

        guard !hasCompleted || !accessibility.hasPermission else { return }

        // Use the single shared manager and the declarative Window
        // to avoid duplicate windows and state desync.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .proprDidFinishLaunching, object: nil)
        }
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

// Full AppKit status item for reliable menubar menu (no SwiftUI hover flicker).
// This gives native macOS menu behavior including proper hover highlighting on submenus.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    func setup() {
        // Remove the SwiftUI MenuBarExtra menu if we want full control (icon stays via this)
        // For now, we create our own status item with the custom icon.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
        }
        
        let menu = buildMainMenu()
        menu.delegate = self
        statusItem?.menu = menu
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
        
        // Permissions if needed
        // (We can add conditional logic here similar to SwiftUI version)
        
        menu.addItem(.separator())
        
        // Quit
        let quit = NSMenuItem(title: "Quit Propr", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
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
        
        let manage = NSMenuItem(title: "Manage Models...", action: #selector(openSettings), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
        
        return submenu
    }
    
    // Rebuild dynamic parts when menu is about to open (keeps it fresh)
    func menuWillOpen(_ menu: NSMenu) {
        // For the top level menu, we can rebuild if needed.
        // For simplicity, we rebuild the model submenu when its parent is the main menu.
        // In practice, call rebuild on the statusItem menu if you want live updates.
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
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Helper notification for opening settings from nested menu
extension Notification.Name {
    static let proprOpenSettings = Notification.Name("proprOpenSettings")
}
