import SwiftUI

/// The Lookup section of the General pane: how the lookup panel behaves.
struct LookupSection: View {
    @AppStorage(SearchProvider.defaultForLookupKey) private var defaultProvider: SearchProvider = .google
    @AppStorage(LookupPreferences.customInstructionsKey) private var customInstructions = ""

    var body: some View {
        Section {
            SettingsRow(
                title: "Open Lookups In",
                systemImage: "rectangle.and.text.magnifyingglass",
                color: .teal,
                subtitle: "You can still switch tabs in the panel."
            ) {
                Picker("Open Lookups In", selection: $defaultProvider) {
                    ForEach(SearchProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
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
                subtitle: "Applied to every AI answer in Quick Lookup.",
                placeholder: "e.g. Define each meaning on its own line with an example.",
                limit: CustomInstructions.limit,
                text: $customInstructions
            )
        } header: {
            Text("Lookup")
        } footer: {
            Text("Separate from the bar's custom instructions. Lookup never changes your text.")
        }
    }
}
