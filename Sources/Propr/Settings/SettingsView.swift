import SwiftUI

/// One pane of the Settings window. The order here is the order of the tabs.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case refine
    case lookup
    case models

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .refine: return "Refine"
        case .lookup: return "Lookup"
        case .models: return "Models"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "command"
        case .refine: return "wand.and.stars"
        case .lookup: return "magnifyingglass"
        case .models: return "cpu.fill"
        }
    }
}

/// The Settings window: the platform's own tab container, one tab per pane.
///
/// This is SwiftUI's `TabView`, which on macOS is an AppKit tab view (`NSTabView`).
/// The tab bar, its selection state, its keyboard behaviour and its appearance —
/// Liquid Glass included — all come from the system rather than from a hand-built
/// strip, so the window keeps up with the platform on its own.
///
/// `Tab` is the macOS 15 API; macOS 14 uses the older `.tabItem`, which draws the
/// same native tabs.
struct SettingsView: View {
    @State private var selection: SettingsSection

    /// - Parameter initialSection: the pane to show when the window is first built.
    ///   Passed in rather than delivered by notification, because the notification
    ///   that asks for it is posted before this view exists to hear it.
    init(initialSection: SettingsSection = .general) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        tabs
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .proprOpenSettings)) { note in
                if let target = note.userInfo?["selectSection"] as? String,
                    let section = SettingsSection(rawValue: target)
                {
                    selection = section
                }
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(macOS 15.0, *) {
            TabView(selection: $selection) {
                Tab("General", systemImage: SettingsSection.general.systemImage, value: .general) {
                    GeneralSettingsView()
                }
                Tab("Shortcuts", systemImage: SettingsSection.shortcuts.systemImage, value: .shortcuts) {
                    ShortcutsSettingsView()
                }
                Tab("Refine", systemImage: SettingsSection.refine.systemImage, value: .refine) {
                    RefineSettingsView()
                }
                Tab("Lookup", systemImage: SettingsSection.lookup.systemImage, value: .lookup) {
                    LookupSettingsView()
                }
                Tab("Models", systemImage: SettingsSection.models.systemImage, value: .models) {
                    ModelsSettingsView()
                }
            }
        } else {
            TabView(selection: $selection) {
                GeneralSettingsView()
                    .tabItem { tabLabel(.general) }
                    .tag(SettingsSection.general)
                ShortcutsSettingsView()
                    .tabItem { tabLabel(.shortcuts) }
                    .tag(SettingsSection.shortcuts)
                RefineSettingsView()
                    .tabItem { tabLabel(.refine) }
                    .tag(SettingsSection.refine)
                LookupSettingsView()
                    .tabItem { tabLabel(.lookup) }
                    .tag(SettingsSection.lookup)
                ModelsSettingsView()
                    .tabItem { tabLabel(.models) }
                    .tag(SettingsSection.models)
            }
        }
    }

    private func tabLabel(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
    }
}

#Preview {
    SettingsView()
        .frame(width: 720, height: 560)
}
