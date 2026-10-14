import AppKit
import SwiftUI
import Testing

@testable import Propr

/// The Settings tabs. Each feature owns one, so these pin down the order, that every
/// pane is labelled, that the menu bar's "Manage Models…" still lands on the right
/// pane by raw value, and that the tabs really do reach the platform's tab container.
struct SettingsSectionTests {
    @Test("The tab bar lists the app's panes in a stable order")
    func order() {
        #expect(SettingsSection.allCases == [.general, .shortcuts, .refine, .lookup, .models])
    }

    @Test("Every pane has its own title and icon")
    func labels() {
        let titles = SettingsSection.allCases.map(\.title)
        let icons = SettingsSection.allCases.map(\.systemImage)

        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
        #expect(Set(icons).count == icons.count)
    }

    @Test("Raw values match the notification the menu bar sends")
    func menuBarContract() {
        // StatusItemController posts "models" for Manage Models…
        #expect(SettingsSection(rawValue: "models") == .models)
        for section in SettingsSection.allCases {
            #expect(SettingsSection(rawValue: section.rawValue) == section)
        }
    }

    /// Propr hosts SwiftUI in an AppKit window, so this checks that the panes land
    /// in the platform's own tab container (`NSTabView`) rather than only looking
    /// like tabs: one item per pane, in order, each carrying its title and icon.
    @MainActor
    @Test("The panes reach the platform tab container")
    func nativeTabView() throws {
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        // Offscreen: the hierarchy still builds and lays out without appearing.
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.view.layoutSubtreeIfNeeded()

        let tabView = try #require(Self.firstTabView(in: hosting.view))
        #expect(tabView.tabViewItems.count == SettingsSection.allCases.count)
        #expect(tabView.tabViewItems.map(\.label) == SettingsSection.allCases.map(\.title))
        #expect(tabView.tabViewItems.allSatisfy { $0.image != nil })
        // Top tabs, the classic settings chrome.
        #expect(tabView.tabViewType == .topTabsBezelBorder)
    }

    @MainActor
    private static func firstTabView(in view: NSView) -> NSTabView? {
        if let tabView = view as? NSTabView { return tabView }
        for subview in view.subviews {
            if let found = firstTabView(in: subview) { return found }
        }
        return nil
    }
}
