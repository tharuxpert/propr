import ServiceManagement
import SwiftUI

/// The General pane.
///
/// A grouped `Form`, which is what gives Mac settings their leading-aligned labels,
/// trailing controls and system section spacing. The previous version stacked
/// hand-drawn material cards inside a ScrollView, which reads as a web page.
struct GeneralSettingsView: View {
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
            } footer: {
                Text("Propr lives in the menu bar and stays out of the way until you summon it.")
            }

            Section("Summoning") {
                LabeledContent("Keyboard Shortcut") {
                    // The shortcut was previously undocumented anywhere in the app,
                    // which made the whole feature undiscoverable.
                    Text("Double-tap ⌘")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Menu Bar") {
                    Text("Show Floating Bar")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Image(
                            systemName: accessibility.hasPermission
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(accessibility.hasPermission ? .green : .orange)

                        Text(accessibility.hasPermission ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                    }
                }

                if !accessibility.hasPermission {
                    LabeledContent("Required to read and edit text in other apps") {
                        Button("Open System Settings…") {
                            accessibility.openAccessibilitySystemSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // The toggle can be changed outside the app (System Settings > Login Items).
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
        .frame(width: 560, height: 480)
}
