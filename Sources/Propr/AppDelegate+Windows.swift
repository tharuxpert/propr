import AppKit
import SwiftUI

// Settings and onboarding windows are built by hand rather than declared as SwiftUI
// scenes: in a pure LSUIElement (menu-bar-only) app the declarative window APIs do
// not reliably open from a status-item menu.
extension AppDelegate {
    @objc func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.showSettingsWindow()
        }
    }

    @MainActor
    func showSettingsWindow() {
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
            window.minSize = NSSize(width: 720, height: 520)
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
