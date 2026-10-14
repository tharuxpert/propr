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
/// A tab strip across the top with one tab per pane, instead of a sidebar: the
/// panes are few and each belongs to a feature, so the whole window can stay one
/// column wide and every pane is a single click away.
struct SettingsView: View {
    @State private var selection: SettingsSection

    /// - Parameter initialSection: the pane to show when the window is first built.
    ///   Passed in rather than delivered by notification, because the notification
    ///   that asks for it is posted before this view exists to hear it.
    init(initialSection: SettingsSection = .general) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(selection: $selection)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
