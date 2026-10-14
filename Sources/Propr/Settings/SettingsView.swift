import SwiftUI

/// One pane of the Settings window. The order here is the order in the sidebar.
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

    var color: Color {
        switch self {
        case .general: return .gray
        case .shortcuts: return .blue
        case .refine: return .purple
        case .lookup: return .teal
        case .models: return .indigo
        }
    }
}

/// The Settings window.
///
/// A `NavigationSplitView` with a real `List` selection, the way System Settings and
/// modern Mac apps are laid out. The previous version drew its own sidebar out of a
/// VStack and `.onTapGesture`, which meant no keyboard navigation, no system
/// highlight and no hover behaviour.
struct SettingsView: View {
    @State private var selection: SettingsSection
    @FocusState private var isSidebarFocused: Bool

    /// - Parameter initialSection: the pane to show when the window is first built.
    ///   Passed in rather than delivered by notification, because the notification
    ///   that asks for it is posted before this view exists to hear it.
    init(initialSection: SettingsSection = .general) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SettingsIcon(systemImage: section.systemImage, color: section.color)
                }
                .tag(section)
            }
            // Start with the sidebar focused. Otherwise, with keyboard navigation on,
            // the first control in the pane opens wearing a focus ring.
            .focused($isSidebarFocused)
            .defaultFocus($isSidebarFocused, true)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .onReceive(NotificationCenter.default.publisher(for: .proprOpenSettings)) { note in
            if let target = note.userInfo?["selectSection"] as? String,
                let section = SettingsSection(rawValue: target)
            {
                selection = section
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .refine:
            RefineSettingsView()
        case .lookup:
            LookupSettingsView()
        case .models:
            ModelsSettingsView()
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 760, height: 620)
}
