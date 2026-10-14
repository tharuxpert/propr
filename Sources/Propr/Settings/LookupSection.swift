import SwiftUI

/// The Lookup section of the General pane: how the lookup panel behaves.
struct LookupSection: View {
    @AppStorage(SearchProvider.defaultForLookupKey) private var defaultProvider: SearchProvider = .google

    var body: some View {
        Section("Lookup") {
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
        }
    }
}
