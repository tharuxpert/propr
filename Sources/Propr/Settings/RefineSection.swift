import SwiftUI

/// The Refine section of the General pane: how the refine bar behaves.
struct RefineSection: View {
    @AppStorage(RefinePreferences.customInstructionsKey) private var customInstructions = ""

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRowLabel(
                    title: "Custom Instructions",
                    systemImage: "text.badge.star",
                    color: .purple,
                    subtitle: "Applied to every edit and answer in the bar."
                )

                TextEditor(text: $customInstructions)
                    .font(.body)
                    .frame(minHeight: 64, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        if customInstructions.isEmpty {
                            Text(verbatim: "e.g. Use British spelling. Keep my casual tone.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: customInstructions) { _, text in
                        if text.count > RefinePreferences.customInstructionsLimit {
                            customInstructions = String(text.prefix(RefinePreferences.customInstructionsLimit))
                        }
                    }

                Text("\(customInstructions.count) / \(RefinePreferences.customInstructionsLimit)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Refine")
        } footer: {
            Text("A request in the bar wins over these when the two disagree. Not used by Quick Lookup.")
        }
    }
}
