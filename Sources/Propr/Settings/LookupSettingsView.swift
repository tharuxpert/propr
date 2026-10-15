import SwiftUI

/// The Lookup pane: how the search panel behaves. Which model it answers with lives
/// in the Models pane, next to the providers those models come from.
struct LookupSettingsView: View {
    @AppStorage(SearchProvider.defaultForLookupKey) private var defaultProvider: SearchProvider = .google
    @AppStorage(LookupPreferences.customInstructionsKey) private var customInstructions = ""

    var body: some View {
        SettingsPane {
            SettingsForm {
                SettingsRow("Open Lookups In") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Open Lookups In", selection: $defaultProvider) {
                            ForEach(SearchProvider.allCases, id: \.self) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        SettingsNote("You can still switch tabs in the panel.")
                    }
                }

                SettingsRow("Custom Instructions") {
                    CustomInstructionsEditor(
                        placeholder: "e.g. Define each meaning on its own line with an example.",
                        note: "Applied to every AI answer in Quick Lookup, separately from the bar's.",
                        limit: CustomInstructions.limit,
                        text: $customInstructions
                    )
                }
            }
        }
    }
}

#Preview {
    LookupSettingsView()
        .frame(width: 780, height: 560)
}
