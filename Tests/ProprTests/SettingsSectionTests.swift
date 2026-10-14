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

    @Test("Raw values match the notification the menu bar sends")
    func menuBarContract() {
        // StatusItemController posts "models" for Manage Models…
        #expect(SettingsSection(rawValue: "models") == .models)
        for section in SettingsSection.allCases {
            #expect(SettingsSection(rawValue: section.rawValue) == section)
        }
    }
}
