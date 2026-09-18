import AppKit
import SwiftUI

// Settings and onboarding windows are built by hand rather than declared as SwiftUI
// scenes: in a pure LSUIElement (menu-bar-only) app the declarative window APIs do
// not reliably open from a status-item menu.
extension AppDelegate {
    @objc func openSettingsWindow(_ note: Notification) {
        // Read the requested pane here. On first open the SettingsView does not exist
        // yet, so the notification would otherwise be lost — "Manage Models…" opened
        // on General.
        let section =
            (note.userInfo?["selectSection"] as? String)
            .flatMap(SettingsSection.init(rawValue:)) ?? .general

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.showSettingsWindow(section: section)
        }
    }

    @MainActor
    func showSettingsWindow(section: SettingsSection = .general) {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView(initialSection: section))
            // Let the window be resized freely; SwiftUI should fill it, not size it.
            hostingController.sizingOptions = []

            // The hosting controller must be the window's *contentViewController*,
            // not just have its view dropped in as contentView. Only then does it
            // bridge the NavigationSplitView's toolbar and titlebar into the window
            // and learn the titlebar's safe area. Without it the sidebar toggle and
            // title showed up but the form slid underneath a phantom toolbar band.
            let window = NSWindow(contentViewController: hostingController)

            // Full-size content lets the sidebar run up under the titlebar, the way
            // System Settings and other split-view Mac apps look.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 760, height: 580))
            window.minSize = NSSize(width: 720, height: 480)

            // The navigationTitle bridge only pushes a title when the selection
            // *changes*, so without this the window opened as "Untitled" until the
            // user switched panes.
            window.title = section.title

            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            // Stay on the current Space like a normal utility window.
            window.collectionBehavior = []
            window.center()

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    @MainActor
    func showOnboardingForPermissionRecovery() {
        // Reset the launch guard so an explicit menu action can show it even on the same launch.
        accessibility.resetOnboardingAttemptFlag()
        showOnboardingWindow()
    }

    @MainActor
    func showOnboardingIfNeededOnLaunch() {
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
    func showOnboardingWindow() {
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

            let contentRect = NSRect(x: 0, y: 0, width: 460, height: 460)
            hosting.frame = contentRect

            let window = NSWindow(
                contentRect: contentRect,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Propr Setup"
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
