import SwiftUI

/// The Refine pane: how the bar behaves. Which model it uses lives in the Models
/// pane, next to the providers those models come from.
struct RefineSettingsView: View {
    @AppStorage(RefinePreferences.customInstructionsKey) private var customInstructions = ""
    @AppStorage(RefinePreferences.startModeKey) private var startMode: RefinePreferences.StartMode = .edit
    @AppStorage(QuickPrompts.key) private var quickPrompts = QuickPrompts.defaults

    var body: some View {
        SettingsPane {
            SettingsForm {
                SettingsRow("Open the Bar In") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Open the Bar In", selection: $startMode) {
                            ForEach(RefinePreferences.StartMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        SettingsNote("Edit changes your text; Ask answers in the bar. Tab switches between them.")
                    }
                }

                SettingsRow("Quick Prompts") {
                    QuickPromptsEditor(prompts: $quickPrompts)
                }

                SettingsRow("Custom Instructions") {
                    CustomInstructionsEditor(
                        placeholder: "e.g. Use British spelling. Keep my casual tone.",
                        note: "Applied to every edit and answer. A request in the bar wins if they disagree.",
                        limit: RefinePreferences.customInstructionsLimit,
                        text: $customInstructions
                    )
                }
            }
        }
    }
}

#Preview {
    RefineSettingsView()
        .frame(width: 780, height: 560)
}
