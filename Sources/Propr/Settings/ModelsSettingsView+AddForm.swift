import SwiftUI

// Adding a custom (BYOK) endpoint. Writes into `addForm`; the rules it enforces
// live in EndpointFormState, shared with the edit flow.
extension ModelsSettingsView {

    var addEndpointForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Endpoint name", text: $addForm.name)
                .textFieldStyle(.roundedBorder)
            if let error = addForm.nameError(in: addContext) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Endpoint URL (e.g. https://api.groq.com/openai/v1)", text: $addForm.baseURL)
                .textFieldStyle(.roundedBorder)
            if let error = addForm.urlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("API Key (e.g. sk-...)", text: $addForm.apiKey)
                .textFieldStyle(.roundedBorder)
            if let error = addForm.apiKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("Models")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 6) {
                TextField("Model ID (e.g. anthropic/claude-3-5-sonnet)", text: $addForm.draftModelName)
                    .textFieldStyle(.roundedBorder)

                TextField("Alias (shown in menu, optional)", text: $addForm.draftModelAlias)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addModelToList()
                } label: {
                    Label("Add model", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(!addForm.canAddDraftModel)

                // Show duplicate error if user is trying to add something invalid
                if !addForm.draftModelName.trimmingCharacters(in: .whitespaces).isEmpty
                    && !addForm.canAddDraftModel
                {
                    Text("This model (or alias) is already in the list")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !addForm.models.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addForm.models) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.displayName)
                                    .fontWeight(model.alias != nil ? .medium : .regular)

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
                    withAnimation {
                        showingAddForm = false
                        resetAddForm()
                        addForm.models = []
                        addForm.draftModelName = ""
                        addForm.draftModelAlias = ""
                    }
                }

                Spacer()

                Button("Add Endpoint") {
                    addEndpoint()
                }
                .disabled(!addForm.canSubmit(in: addContext))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }


    func addModelToList() {
        addForm.addDraftModel()
    }

    func removeModelFromList(_ model: CustomModel) {
        addForm.removeModel(model)
    }


    func addEndpoint() {
        guard let endpoint = addForm.makeEndpoint(in: addContext) else { return }

        do {
            try modelStore.saveAPIKey(addForm.apiKey, for: endpoint.id)
            modelStore.addEndpoint(endpoint)

            // Reset form + model picker state
            resetAddForm()
            showingAddForm = false
            addForm.models = []
            addForm.draftModelName = ""
            addForm.draftModelAlias = ""

            // Auto-select the first model from the new endpoint
            if let firstModel = endpoint.models.first {
                let selection = ModelSelection(
                    id: firstModel.id,
                    displayName: firstModel.displayName,
                    endpointID: endpoint.id,
                    modelName: firstModel.name,
                    baseURL: endpoint.baseURL
                )
                modelStore.selectModel(selection)
            }
        } catch {
            print("Failed to save API key: \(error)")
            keychainErrorMessage = error.localizedDescription
        }
    }


    func resetAddForm() {
        addForm = EndpointFormState()
        quickAddBaseURL = ""
    }

}
