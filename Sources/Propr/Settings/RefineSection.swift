import SwiftUI

/// The Refine section of the General pane: how the refine bar behaves.
struct RefineSection: View {
    @AppStorage(RefinePreferences.customInstructionsKey) private var customInstructions = ""
    @AppStorage(RefinePreferences.startModeKey) private var startMode: RefinePreferences.StartMode = .edit

    var body: some View {
        Section {
            SettingsRow(
                title: "Open the Bar In",
                systemImage: "rectangle.and.pencil.and.ellipsis",
                color: .blue,
                subtitle: "Edit changes your text; Ask answers in the bar. Tab switches."
            ) {
                Picker("Open the Bar In", selection: $startMode) {
                    ForEach(RefinePreferences.StartMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            CustomInstructionsEditor(
                title: "Custom Instructions",
                systemImage: "text.badge.star",
                color: .purple,
                subtitle: "Applied to every edit and answer in the bar.",
                placeholder: "e.g. Use British spelling. Keep my casual tone.",
                limit: RefinePreferences.customInstructionsLimit,
                text: $customInstructions
            )
        } header: {
            Text("Refine")
        } footer: {
            Text("When a request in the bar disagrees with your custom instructions, the request wins.")
        }
    }
}
