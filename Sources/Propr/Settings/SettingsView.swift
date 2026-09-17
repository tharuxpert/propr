import ServiceManagement
import SwiftUI

enum SettingsSection: String, CaseIterable {
    case general
    case models

    var title: String {
        switch self {
        case .models: return "Models"
        case .general: return "General"
        }
    }

    var systemImage: String {
        switch self {
        case .models: return "cpu"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (fixed width, contained look matching the reference)
            Sidebar(selection: $selectedSection)
                .frame(width: 210)

            Divider()

            // Content pane — fills remaining space, lets inner views scroll as needed
            Group {
                switch selectedSection {
                case .models:
                    ModelsSettingsView()
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onChange(of: selectedSection) { _, newSection in
            updateWindowTitle(to: newSection)
        }
        .onAppear {
            updateWindowTitle(to: selectedSection)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.proprOpenSettings)) {
            note in
            if let target = note.userInfo?["selectSection"] as? String,
                target == "models"
            {
                selectedSection = .models
            }
        }
    }

    private func updateWindowTitle(to section: SettingsSection) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.title = "Settings — \(section.title)"
        }
    }
}

// MARK: - Custom Sidebar (blue pill selection to match the reference screenshot)

private struct Sidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                SidebarRow(
                    title: section.title,
                    systemImage: section.systemImage,
                    isSelected: selection == section
                ) {
                    selection = section
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - General (now with real Launch at Login in the screenshot card style)

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Status section card (styled like the reference screenshot)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch at Login")
                                .font(.subheadline.weight(.medium))

                            Text("Automatically start Propr when you log in to your Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

                // Future items placeholder (keeps visual weight similar to the reference)
                VStack(alignment: .leading, spacing: 8) {
                    Text("More settings coming soon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: launchAtLogin) { _, newValue in
            updateLaunchAtLogin(newValue)
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
            print(
                "[Propr] Failed to \(enabled ? "register" : "unregister") launch at login: \(error)"
            )
            // Toggle state is left as-is; user can flip it again to retry.
        }
    }
}

#Preview {
    SettingsView()
}
