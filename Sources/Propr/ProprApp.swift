import SwiftUI

@main
struct ProprApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu bar only. No main window scene on purpose.
        MenuBarExtra("Propr", systemImage: "sparkles") {
            Button("Settings...") {
                openWindow(id: "settings")
            }

            Divider()

            Button("Quit Propr") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        // Settings window (will be expanded later on its own branch)
        Window("Propr Settings", id: "settings") {
            SettingsPlaceholderView()
                .frame(width: 420, height: 280)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// Temporary placeholder so the Settings button does something visible.
// This whole view + window will be replaced with real settings on a later branch.
struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

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
