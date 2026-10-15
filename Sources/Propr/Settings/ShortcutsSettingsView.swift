import SwiftUI

/// The Shortcuts pane: each gesture that summons Propr, with a checkbox to turn it
/// off, and any system shortcut it collides with.
struct ShortcutsSettingsView: View {
    @AppStorage(TriggerPreferences.refineDoubleTapKey) private var refineEnabled = true
    @AppStorage(TriggerPreferences.fnLookupKey) private var fnEnabled = true
    @AppStorage(TriggerPreferences.forceClickLookupKey) private var forceClickEnabled = true

    private let shortcutConflicts = ShortcutConflictMonitor.shared

    /// A clash only matters while the trigger it clashes with is switched on.
    private var activeConflicts: [ShortcutConflict] {
        shortcutConflicts.conflicts.filter { conflict in
            switch conflict.kind {
            case .fnKey: fnEnabled
            case .forceClickLookUp: forceClickEnabled
            }
        }
    }

    var body: some View {
        SettingsPane {
            SettingsForm {
                Section {
                    SettingsRow("Refine Text") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $refineEnabled) {
                                shortcutLabel(keys: ["⌘", "⌘"], text: "Double-tap Command")
                            }
                            SettingsNote(
                                "Opens the floating bar in any text field. You can also choose Show Floating Bar from the menu bar icon."
                            )
                        }
                    }
                }

                Section {
                    SettingsRow("Quick Lookup") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $fnEnabled) {
                                shortcutLabel(keys: ["fn"], text: "Tap Fn on selected text")
                            }
                            Toggle("Force Click a word on the trackpad", isOn: $forceClickEnabled)
                            SettingsNote(
                                "Lookup opens a separate panel and never changes your text. Turning Force Click off gives it back to macOS Look Up."
                            )
                            if !activeConflicts.isEmpty {
                                ShortcutConflictList(conflicts: activeConflicts)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func shortcutLabel(keys: [String], text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    SettingsKeycap(symbol: key)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 780, height: 560)
}
