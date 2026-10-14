import SwiftUI

/// The Shortcuts pane: each gesture that summons Propr, with a switch to turn it
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
        Form {
            Section {
                SettingsRow(
                    title: "Refine Text",
                    systemImage: "command",
                    color: .blue,
                    subtitle: "Double-tap Command in any text field."
                ) {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            SettingsKeycap(symbol: "⌘")
                            SettingsKeycap(symbol: "⌘")
                        }
                        .accessibilityLabel("Double-tap Command")
                        triggerSwitch("Refine Text", isOn: $refineEnabled)
                    }
                }

                SettingsRow(
                    title: "Look Up with Fn",
                    systemImage: "magnifyingglass",
                    color: .teal,
                    subtitle: "Tap Fn on selected text."
                ) {
                    HStack(spacing: 10) {
                        SettingsKeycap(symbol: "fn")
                        triggerSwitch("Look Up with Fn", isOn: $fnEnabled)
                    }
                }

                SettingsRow(
                    title: "Look Up with Force Click",
                    systemImage: "hand.tap",
                    color: .teal,
                    subtitle: "Press firmly on a word with a Force Touch trackpad."
                ) {
                    triggerSwitch("Look Up with Force Click", isOn: $forceClickEnabled)
                }

                if !activeConflicts.isEmpty {
                    ShortcutConflictList(conflicts: activeConflicts)
                }
            } footer: {
                Text(
                    "Lookup opens a separate panel and never changes your text. Turning Force Click off gives it back to macOS Look Up. You can also choose Show Floating Bar from the Propr menu bar icon."
                )
            }
        }
        .formStyle(.grouped)
    }

    private func triggerSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

#Preview {
    ShortcutsSettingsView()
        .frame(width: 560, height: 420)
}
