import ServiceManagement
import SwiftUI

/// The General pane.
///
/// A grouped `Form`, which is what gives Mac settings their leading-aligned labels,
/// trailing controls and system section spacing. Rows carry System Settings style
/// badges so each one can be found at a glance.
struct GeneralSettingsView: View {
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                appHeader
            }

            Section {
                SettingsRow(
                    title: "Launch at Login",
                    systemImage: "power",
                    color: .gray,
                    subtitle: "Keep Propr ready in the menu bar."
                ) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            updateLaunchAtLogin(enabled)
                        }
                }
            }

            SummoningSection()

            RefineSection()

            LookupSection()

            Section("Permissions") {
                SettingsRow(
                    title: "Accessibility",
                    systemImage: "accessibility",
                    color: .blue,
                    subtitle: "Lets Propr read and edit text in other apps."
                ) {
                    permissionBadge(granted: accessibility.hasPermission)
                }

                if !accessibility.hasPermission {
                    HStack {
                        Spacer()
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

    /// The app's identity at the top of the pane, like the account card in System
    /// Settings, so the window does not open on a lone toggle.
    private var appHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Propr")
                    .font(.title3.weight(.semibold))
                Text("Refine or look up any text, right where you are.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Version \(appVersion)")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func permissionBadge(granted: Bool) -> some View {
        Label(
            granted ? "Granted" : "Not Granted",
            systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.callout.weight(.medium))
        .foregroundStyle(granted ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill((granted ? Color.green : Color.orange).opacity(0.15)))
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
