import SwiftUI

/// The Models pane: which model Propr uses, and the providers that supply them.
///
/// A grouped `Form` like the General pane, so both panes share one look. Each
/// provider row carries its own Edit and Remove, and adding or editing happens in
/// a sheet rather than in forms that expand inline inside a scroll view.
struct ModelsSettingsView: View {
    @State private var modelStore = ModelStore.shared

    @State private var editingEndpoint: CustomEndpoint?
    @State private var isAddingEndpoint = false
    @State private var removingEndpoint: CustomEndpoint?
    @State private var keychainErrorMessage: String?

    var body: some View {
        Group {
            if modelStore.customEndpoints.isEmpty {
                emptyState
            } else {
                form
            }
        }
        .confirmationDialog(
            "Remove \(removingEndpoint?.name ?? "this provider")?",
            isPresented: Binding(
                get: { removingEndpoint != nil },
                set: { if !$0 { removingEndpoint = nil } }),
            presenting: removingEndpoint
        ) { endpoint in
            Button("Remove", role: .destructive) { delete(endpoint.id) }
        } message: { _ in
            Text("Its models and saved API key will be deleted.")
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

    private var form: some View {
        Form {
            Section {
                SettingsRow(
                    title: "Default Model",
                    systemImage: "star.fill",
                    color: .orange,
                    subtitle: "Used each time you summon Propr."
                ) {
                    defaultModelPicker
                }
            } footer: {
                Text("You can also switch models from the Propr menu bar icon.")
            }

            Section("Providers") {
                ForEach(modelStore.customEndpoints) { endpoint in
                    EndpointRow(
                        endpoint: endpoint,
                        onEdit: { editingEndpoint = endpoint },
                        onRemove: { removingEndpoint = endpoint }
                    )
                }

                Button {
                    isAddingEndpoint = true
                } label: {
                    Label("Add Provider…", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
    }

    private var defaultModelPicker: some View {
        Picker("Default Model", selection: selectedModelBinding) {
            if modelStore.selectedModel() == nil {
                Text("None").tag(UUID?.none)
            }
            ForEach(modelStore.customEndpoints) { endpoint in
                if !endpoint.models.isEmpty {
                    Section(endpoint.name) {
                        ForEach(endpoint.models) { model in
                            Text(model.displayName).tag(UUID?.some(model.id))
                        }
                    }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(modelStore.allAvailableModels.isEmpty)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Providers", systemImage: "cpu")
        } description: {
            Text("Add an OpenAI-compatible provider to start refining text.")
        } actions: {
            Button("Add Provider…") { isAddingEndpoint = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private var selectedModelBinding: Binding<UUID?> {
        Binding(
            get: { modelStore.selectedModel()?.id },
            set: { id in
                guard let model = modelStore.allAvailableModels.first(where: { $0.id == id }) else { return }
                modelStore.selectModel(model)
            }
        )
    }

    // MARK: - Actions

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
