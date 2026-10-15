import ServiceManagement
import SwiftUI

/// The General pane: app-level settings that are not about a feature. The refine
/// bar, Quick Lookup, the summoning shortcuts and the models each have a pane of
/// their own, so this one stays short.
struct GeneralSettingsView: View {
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        SettingsPane {
            appHeader

            SettingsForm {
                SettingsRow("Startup") {
                    Toggle("Launch Propr at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLaunchAtLogin(enabled)
                        }
                }

                SettingsRow("Accessibility") {
                    VStack(alignment: .leading, spacing: 8) {
                        permissionStatus(granted: accessibility.hasPermission)
                        SettingsNote("Lets Propr read and edit text in other apps.")
                        if !accessibility.hasPermission {
                            Button("Open System Settings…") {
                                accessibility.openAccessibilitySystemSettings()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // The toggle can be changed outside the app (System Settings > Login Items).
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// The app's identity at the top of the pane, so the window does not open on a
    /// lone checkbox.
    private var appHeader: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Propr")
                .font(.title2.weight(.semibold))
            Text("Refine or look up any text, right where you are.")
                .foregroundStyle(.secondary)
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func permissionStatus(granted: Bool) -> some View {
        Label {
            Text(granted ? "Granted" : "Not granted")
        } icon: {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Propr] Failed to \(enabled ? "register" : "unregister") launch at login: \(error)")
            // Put the toggle back where it was so it never lies about the real state.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 780, height: 560)
}
