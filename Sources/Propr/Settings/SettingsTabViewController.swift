import AppKit
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
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .refine: return "wand.and.stars"
        case .lookup: return "magnifyingglass"
        case .models: return "cpu"
        }
    }
}

extension SettingsSection {
    /// The pane's SwiftUI content.
    @MainActor
    var pane: AnyView {
        switch self {
        case .general: return AnyView(GeneralSettingsView())
        case .shortcuts: return AnyView(ShortcutsSettingsView())
        case .refine: return AnyView(RefineSettingsView())
        case .lookup: return AnyView(LookupSettingsView())
        case .models: return AnyView(ModelsSettingsView())
        }
    }
}

/// The Settings window's content: AppKit's own settings-window pattern, a tab view
/// controller whose tabs live in the window toolbar (`.toolbar` tab style). Paired
/// with the window's `.preference` toolbar style, that gives the icon-over-label
/// toolbar buttons of System Settings-era apps and Raycast, with the selection,
/// keyboard behaviour and Liquid Glass all drawn by the system.
///
/// Each pane is SwiftUI, hosted in its own controller.
final class SettingsTabViewController: NSTabViewController {
    init(initialSection: SettingsSection = .general) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // The window keeps its "Propr Settings" title; the selected toolbar item
        // already says which pane is showing.
        canPropagateSelectedChildViewControllerTitle = false

        for section in SettingsSection.allCases {
            let hosting = NSHostingController(rootView: section.pane)
            // The window sets the size; SwiftUI fills it rather than sizing it, so
            // switching panes does not jump the window around.
            hosting.sizingOptions = []
            let item = NSTabViewItem(viewController: hosting)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.systemImage, accessibilityDescription: section.title)
            item.identifier = section.rawValue
            addTabViewItem(item)
        }
        select(initialSection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var selectedSection: SettingsSection? {
        guard selectedTabViewItemIndex >= 0 else { return nil }
        return SettingsSection.allCases[selectedTabViewItemIndex]
    }

    func select(_ section: SettingsSection) {
        guard let index = SettingsSection.allCases.firstIndex(of: section) else { return }
        selectedTabViewItemIndex = index
    }
}
