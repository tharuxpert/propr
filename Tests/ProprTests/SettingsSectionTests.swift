import AppKit
import SwiftUI
import Testing

@testable import Propr

/// The Settings tabs. Each feature owns one, so these pin down the order, that every
/// pane is labelled, that the menu bar's "Manage Models…" still lands on the right
/// pane by raw value, and that the tabs really do reach the window's settings toolbar.
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

    /// The panes must reach AppKit's settings-window toolbar, not just look like
    /// tabs: one selectable toolbar item per pane, in order, each with its title and
    /// icon, in a `.preference` style toolbar.
    @MainActor
    @Test("The panes are the window's settings toolbar")
    func toolbarTabs() throws {
        let tabs = SettingsTabViewController(initialSection: .models)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .resizable]
        window.toolbarStyle = .preference
        window.setContentSize(NSSize(width: 720, height: 560))
        // Offscreen: the hierarchy still builds and lays out without appearing.
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.selectedSection == .models)

        let toolbar = try #require(window.toolbar)
        // Spacers sit between the tabs; the tabs themselves are the selectable items.
        let items = toolbar.items.filter { $0.itemIdentifier != .space }
        #expect(toolbar.items.count == items.count * 2 - 1)
        #expect(items.map(\.label) == SettingsSection.allCases.map(\.title))
        #expect(items.allSatisfy { $0.image != nil })
        #expect(toolbar.selectedItemIdentifier == items.last?.itemIdentifier)

        tabs.select(.shortcuts)
        #expect(tabs.selectedSection == .shortcuts)
        #expect(toolbar.selectedItemIdentifier == items[1].itemIdentifier)
    }
}
