import SwiftUI

/// The Models pane: the endpoints you have configured, and the models each exposes.
///
/// A `List` with the standard add/remove buttons beneath it — the layout Mail, Xcode
/// and System Settings use for account lists. Adding and editing happen in a sheet
/// rather than in forms that expand inline inside a scroll view.
struct ModelsSettingsView: View {
    @State private var modelStore = ModelStore.shared

    @State private var selection: CustomEndpoint.ID?
    @State private var editingEndpoint: CustomEndpoint?
    @State private var isAddingEndpoint = false
    @State private var keychainErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if modelStore.customEndpoints.isEmpty {
                emptyState
            } else {
                endpointList
            }

            Divider()
            listControls
        }
        .sheet(isPresented: $isAddingEndpoint) {
            EndpointEditorSheet(
                endpoint: nil,
                existingEndpoints: modelStore.customEndpoints,
                initialAPIKey: "",
                onSave: { endpoint, key in add(endpoint, apiKey: key) }
            )
        }
        .sheet(item: $editingEndpoint) { endpoint in
            EndpointEditorSheet(
                endpoint: endpoint,
                existingEndpoints: modelStore.customEndpoints,
                initialAPIKey: modelStore.apiKey(for: endpoint.id) ?? "",
                onSave: { updated, key in update(updated, apiKey: key) }
            )
        }
        .alert(
            "Could not save the API key",
            isPresented: Binding(
                get: { keychainErrorMessage != nil },
                set: { if !$0 { keychainErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { keychainErrorMessage = nil }
        } message: {
            // Keys live in the Keychain, where a write can genuinely fail. Failing
            // silently would leave the endpoint looking configured while refining
            // reports a missing key.
            Text(keychainErrorMessage ?? "")
        }
    }

    // MARK: - Pieces

    private var endpointList: some View {
        List(selection: $selection) {
            ForEach(modelStore.customEndpoints) { endpoint in
                EndpointRow(endpoint: endpoint)
                    .tag(endpoint.id)
                    .contextMenu {
                        Button("Edit…") { editingEndpoint = endpoint }
                        Button("Remove", role: .destructive) { delete(endpoint.id) }
                    }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand { if let selection { delete(selection) } }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Endpoints", systemImage: "brain")
        } description: {
            Text("Add an OpenAI-compatible provider to start refining text.")
        } actions: {
            Button("Add Endpoint…") { isAddingEndpoint = true }
        }
        .frame(maxHeight: .infinity)
    }

    /// The small +/− pair beneath a list, as used throughout macOS.
    private var listControls: some View {
        HStack(spacing: 0) {
            Button {
                isAddingEndpoint = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .help("Add an endpoint")

            Button {
                if let selection { delete(selection) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .disabled(selection == nil)
            .help("Remove the selected endpoint")

            Spacer()

            if let selection, let endpoint = endpoint(for: selection) {
                Button("Edit…") { editingEndpoint = endpoint }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func endpoint(for id: CustomEndpoint.ID) -> CustomEndpoint? {
        modelStore.customEndpoints.first { $0.id == id }
    }

    private func add(_ endpoint: CustomEndpoint, apiKey: String) {
        do {
            try modelStore.saveAPIKey(apiKey, for: endpoint.id)
            modelStore.addEndpoint(endpoint)
            selectFirstModelIfNeeded(of: endpoint)
        } catch {
            keychainErrorMessage = error.localizedDescription
        }
    }

    private func update(_ endpoint: CustomEndpoint, apiKey: String) {
        do {
            try modelStore.saveAPIKey(apiKey, for: endpoint.id)
            modelStore.updateEndpoint(endpoint)
            selectFirstModelIfNeeded(of: endpoint)
        } catch {
            keychainErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ id: CustomEndpoint.ID) {
        modelStore.deleteEndpoint(id: id)
        if selection == id { selection = nil }
    }

    /// Leaves the user with something selected after they configure a provider, so
    /// the first refine does not fail with "no model selected".
    private func selectFirstModelIfNeeded(of endpoint: CustomEndpoint) {
        guard modelStore.selectedModel() == nil, let first = endpoint.models.first else { return }

        modelStore.selectModel(
            ModelSelection(
                id: first.id,
                displayName: first.displayName,
                endpointID: endpoint.id,
                modelName: first.name,
                baseURL: endpoint.baseURL
            )
        )
    }
}

#Preview {
    ModelsSettingsView()
        .frame(width: 560, height: 480)
}
