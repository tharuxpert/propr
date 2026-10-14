import Testing

@testable import Propr

/// The Settings panes. Each feature owns one, so these pin down the sidebar order,
/// that every pane is labelled, and that the menu bar's "Manage Models…" still lands
/// on the right pane by raw value.
struct SettingsSectionTests {
    @Test("The sidebar lists the app's panes in a stable order")
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

    @Test("Arrow keys wrap around the tab strip")
    func moved() {
        #expect(SettingsSection.moved(from: .general, by: 1) == .shortcuts)
        #expect(SettingsSection.moved(from: .models, by: 1) == .general)
        #expect(SettingsSection.moved(from: .general, by: -1) == .models)
        #expect(SettingsSection.moved(from: .lookup, by: -1) == .refine)
        #expect(SettingsSection.moved(from: .refine, by: 0) == .refine)
        // A move longer than the strip still lands inside it.
        #expect(SettingsSection.moved(from: .general, by: SettingsSection.allCases.count) == .general)
    }

    @Test("Raw values match the notification the menu bar sends")
    func menuBarContract() {
        // StatusItemController posts "models" for Manage Models…
        #expect(SettingsSection(rawValue: "models") == .models)
        for section in SettingsSection.allCases {
            #expect(SettingsSection(rawValue: section.rawValue) == section)
        }
    }
}
