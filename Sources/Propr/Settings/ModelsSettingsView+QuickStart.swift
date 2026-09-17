import SwiftUI

// The Quick Start flow: pick a known provider, paste a key, choose models.
// It is the add flow with the name and base URL prefilled, so it shares `addForm`
// and therefore the same validation rules.
extension ModelsSettingsView {
    /// The Quick Start provider form, shown once a provider tile is picked.
    /// Wrapped in its own VStack so the expand/collapse animation stays scoped to it.
    @ViewBuilder
    var quickAddForm: some View {
        // Quick Add Form (appears when a provider is selected)
        // We wrap it so we can scope the smooth expand/collapse animation
        // (same treatment as the BYOK custom form).
        VStack {
            if let provider = quickAddProvider {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add \(provider.name)")
                        .font(.headline)

                    if provider.requiresKey {
                        SecureField(
                            provider.apiKeyExample ?? "API Key", text: $quickAddAPIKey
                        )
                        .textFieldStyle(.roundedBorder)
                    } else {
                        // For Local providers the base URL is critical and frequently customized
                        // (different ports for LM Studio, OLLAMA_HOST changes, LAN, Docker, WSL, etc.)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(.subheadline.weight(.medium))

                            TextField(
                                "http://127.0.0.1:11434/v1", text: $quickAddBaseURL
                            )
                            .textFieldStyle(.roundedBorder)

                            Text(
                                "Ollama default is 11434. LM Studio default is 1234. Use 127.0.0.1 for best compatibility with Docker/WSL. Change the port or host if you modified OLLAMA_HOST or the LM Studio server settings."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Same model + alias picker as custom BYOK
                    Divider()

                    Text("Models to include")
                        .font(.subheadline.weight(.medium))

                    VStack(alignment: .leading, spacing: 6) {
                        let isLocal = !(quickAddProvider?.requiresKey ?? true)

                        TextField(
                            isLocal
                                ? "Model name (e.g. llama3.1 or qwen2.5:14b)"
                                : "Model ID (exact string sent to the API)",
                            text: $addForm.draftModelName
                        )
                        .textFieldStyle(.roundedBorder)

                        if isLocal {
                            Text(
                                "Must match exactly what you see in `ollama list` or LM Studio"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        TextField(
                            "Alias (optional – what shows in Propr’s menu)",
                            text: $addForm.draftModelAlias
                        )
                        .textFieldStyle(.roundedBorder)

                        Button {
                            addModelToList()
                        } label: {
                            Label("Add model", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            addForm.draftModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !addForm.models.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Models to add")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(addForm.models) { model in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.displayName)
                                            .fontWeight(
                                                model.alias != nil ? .medium : .regular)

                                        if model.alias != nil {
                                            Text(model.name)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()

                                    Button {
                                        removeModelFromList(model)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Button("Cancel") {
                            quickAddProvider = nil
                            quickAddAPIKey = ""
                            quickAddBaseURL = ""
                            addForm.models = []
                            addForm.draftModelName = ""
                            addForm.draftModelAlias = ""
                        }

                        Spacer()

                        Button("Add \(provider.name)") {
                            addQuickProvider()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (provider.requiresKey
                                && quickAddAPIKey.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty)
                                || (!provider.requiresKey
                                    && (quickAddBaseURL.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty
                                        || EndpointURLValidator.normalizedBaseURL(from: quickAddBaseURL) == nil))
                                || addForm.models.isEmpty
                        )
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.8), value: quickAddProvider != nil
        )

    }

    func startQuickAdd(for provider: BuiltInProvider) {
        quickAddProvider = provider
        quickAddAPIKey = ""
        quickAddBaseURL = provider.baseURL  // prefill with the provider's default (user can edit for Local)

        // Start empty so the user manually adds exactly the models they want
        // (with aliases), same as the custom BYOK flow.
        addForm.models = []
    }


    func addQuickProvider() {
        guard let provider = quickAddProvider else { return }

        let trimmedKey = quickAddAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = quickAddBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // For local providers we don't require a key, but we do require a valid base URL
        if provider.requiresKey && trimmedKey.isEmpty { return }
        guard let normalizedURL = EndpointURLValidator.normalizedBaseURL(from: trimmedURL) else { return }

        // Use whatever models + aliases the user curated in the list (same as custom endpoint flow)
        let models = addForm.models

        // For Local quick-add we respect the normalized URL the user entered.
        let finalBaseURL = provider.requiresKey ? provider.baseURL : normalizedURL

        let endpoint = CustomEndpoint(
            name: provider.name,
            baseURL: finalBaseURL,
            models: models
        )

        do {
            if provider.requiresKey {
                try modelStore.saveAPIKey(trimmedKey, for: endpoint.id)
            }

            modelStore.addEndpoint(endpoint)

            // Auto-select the first model
            if let first = endpoint.models.first {
                let selection = ModelSelection(
                    id: first.id,
                    displayName: first.displayName,
                    endpointID: endpoint.id,
                    modelName: first.name,
                    baseURL: endpoint.baseURL
                )
                modelStore.selectModel(selection)
            }

            // Reset quick add state + the shared model list
            quickAddProvider = nil
            quickAddAPIKey = ""
            quickAddBaseURL = ""
            addForm.models = []
            addForm.draftModelName = ""
            addForm.draftModelAlias = ""

        } catch {
            print("Failed to save API key for quick provider: \(error)")
            keychainErrorMessage = error.localizedDescription
        }
    }


}
