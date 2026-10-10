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
    // This avoids duplicate managers and controllers in a menu-bar-only LSUIElement app.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var accessibility: AccessibilityManager { appDelegate.accessibility }

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
// Marked @MainActor because it owns @MainActor-isolated objects (AccessibilityManager, controller)
// and all delegate callbacks + AX work happen on the main thread anyway.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Long-lived core objects owned by the delegate (reliable lifetime in LSUIElement apps).
    let accessibility = AccessibilityManager.shared
    // Eagerly created so menu/hotkey summons can reuse one controller for the app lifetime.
    private let floatingBarController: FloatingBarController
    private let searchPanelController: SearchPanelController
    private var searchTriggerService: SearchTriggerService?
    private var searchGeneration = 0

    // Double-tap Command key detection for quick summon
    private let commandTapDetector = CommandDoubleTapDetector()
    private var commandKeyMonitor: Any?

    // Lazily-created windows presented manually via NSWindow + NSHostingView.
    // This is required for reliable "Settings..." / "Manage Models..." and first-launch
    // onboarding in a pure LSUIElement (menu-bar-only) agent app.
    // Internal rather than private: AppDelegate+Windows.swift needs them, and
    // Swift's `private` is scoped to the file.
    var onboardingWindow: NSWindow?
    var settingsWindow: NSWindow?

    static let summonFloatingBarNotification = Notification.Name("ProprSummonFloatingBar")

    /// True when Xcode launched this process as the host for the unit tests.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // Allow the AppKit menu controller to trigger onboarding/permission UI without tight coupling.
    static weak var shared: AppDelegate?

    override init() {
        floatingBarController = FloatingBarController()
        searchPanelController = SearchPanelController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // The test suite runs inside a copy of the app. Without this it would add a
        // second menu bar icon and a second ⌘⌘ listener for the length of the run.
        guard !Self.isHostingTests else { return }

        // Kick an initial permission check
        accessibility.startMonitoring()
        accessibility.checkPermission(prompt: false)

        // Double-Command key summon
        setupDoubleCommandHotkey()
        setupSearchLookupTriggers()

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
            selector: #selector(openSettingsWindow(_:)),
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

    func applicationWillTerminate(_ notification: Notification) {
        searchTriggerService?.stop()
        searchTriggerService = nil
        if let commandKeyMonitor {
            NSEvent.removeMonitor(commandKeyMonitor)
        }
        commandKeyMonitor = nil
    }

    private func setupDoubleCommandHotkey() {
        // The handler is a `nonisolated static` function, passed by reference — not a
        // closure written here.
        //
        // A closure written inside this method inherits the class's @MainActor
        // isolation (it is not @Sendable), and because it is handed to an Objective-C
        // API the compiler cannot vouch for, Swift inserts a runtime "am I on the main
        // actor?" assertion at its entry. That assertion is what was crashing — every
        // report was EXC_BAD_ACCESS inside swift_task_isCurrentExecutor, called from
        // this callback. Removing captures or changing the body does not help, because
        // neither changes the inherited isolation. Declaring the handler nonisolated
        // does: there is then no assertion to run.
        //
        // Key presses and clicks are watched too: they are what tell a ⌘ tap apart
        // from ⌘ used in a shortcut such as ⌘C or ⌘-click.
        commandKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: AppDelegate.handleCommandHotkeyEvent
        )
    }

    /// Runs on AppKit's event-monitor callback. Nonisolated by declaration, so no
    /// actor-isolation check is emitted at its entry.
    nonisolated private static func handleCommandHotkeyEvent(_ event: NSEvent) {
        // Read only Sendable values; the NSEvent itself must not be carried into the
        // task. keyCode is only valid on keyboard events, so mouse events skip it.
        guard event.type == .flagsChanged else {
            Task { @MainActor in
                AppDelegate.shared?.commandTapDetector.interrupt()
            }
            return
        }
        let keyCode = event.keyCode
        let flags = event.modifierFlags
        let time = event.timestamp

        // Enqueue onto the main actor. Creating a Task does not ask the runtime which
        // executor we are currently on, which is the call that was failing.
        Task { @MainActor in
            AppDelegate.shared?.handleCommandFlagsChanged(keyCode: keyCode, flags: flags, at: time)
        }
    }

    /// Feeds a modifier change to the detector, summoning the bar on a double tap.
    @MainActor
    private func handleCommandFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, at time: TimeInterval) {
        if commandTapDetector.flagsChanged(keyCode: keyCode, flags: flags, at: time) {
            summonFloatingBar()
        }
    }

    @MainActor
    func summonFloatingBar() {
        searchGeneration += 1
        searchPanelController.hide()
        floatingBarController.summonForCurrentFocus()
    }

    private func setupSearchLookupTriggers() {
        searchPanelController.onDismiss = { [weak self] in
            self?.searchGeneration += 1
            SelectionCaptureService.shared.clearPreClickSelection()
        }
        let triggers = SearchTriggerService(
            onFn: { [weak self] in
                guard let self else { return }
                SelectionCaptureService.shared.clearPreClickSelection()
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                self.summonSearch(pid: pid, gestureID: nil, near: nil)
            },
            onMouseDown: { gestureID, pid, point in
                SelectionCaptureService.shared.recordMouseDown(
                    gestureID: gestureID, pid: pid, at: point)
            },
            onForceClick: { [weak self] gestureID, pid, point in
                self?.summonSearch(pid: pid, gestureID: gestureID, near: point)
            }
        )
        searchTriggerService = triggers
        triggers.start()
    }

    private func summonSearch(pid: pid_t, gestureID: UUID?, near point: CGPoint?) {
        guard pid != 0, pid != getpid() else { return }
        searchGeneration += 1
        let generation = searchGeneration

        Task { @MainActor [weak self] in
            var query = await SelectionCaptureService.shared.lookupSelection(
                pid: pid, gestureID: gestureID, at: point) ?? ""
            guard let self, self.searchGeneration == generation,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }

            var capturePermissionRequired = false
            if query.isEmpty, let point {
                switch await PointerOCRService.lookupWord(at: point) {
                case .word(let word): query = word
                case .permissionRequired: capturePermissionRequired = true
                case .noWord: break
                }
            }
            guard self.searchGeneration == generation,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            else { return }

            self.floatingBarController.hide()
            self.searchPanelController.show(
                query: query, near: point,
                capturePermissionRequired: capturePermissionRequired)
        }
    }
}
