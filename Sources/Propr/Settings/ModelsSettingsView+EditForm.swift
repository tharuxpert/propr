import SwiftUI

// Editing an existing endpoint. Writes into `editForm`, validated against every
// other endpoint (see `editContext(for:)`) so it does not clash with itself.
extension ModelsSettingsView {
    func editFormID(for endpointID: UUID) -> String {
        "edit-endpoint-\(endpointID.uuidString)"
    }

    func scrollToEditForm(_ endpointID: UUID, with proxy: ScrollViewProxy) {
        // Scroll to a marker after the edit form so opening near the bottom visibly
        // moves the viewport down to reveal the newly inserted controls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo(editFormID(for: endpointID), anchor: .bottom)
            }
        }

        // Run once more after the transition/layout settles; this makes the scroll
        // reliable for taller forms and smaller settings windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                proxy.scrollTo(editFormID(for: endpointID), anchor: .bottom)
            }
        }
    }


    func editEndpointForm(for endpoint: CustomEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(endpoint.name)")
                .font(.headline)

            TextField("Endpoint name", text: $editForm.name)
                .textFieldStyle(.roundedBorder)
            if let error = editForm.nameError(in: editContext(for: endpoint)) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Endpoint URL", text: $editForm.baseURL)
                .textFieldStyle(.roundedBorder)
            if let error = editForm.urlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("API Key", text: $editForm.apiKey)
                .textFieldStyle(.roundedBorder)
            if let error = editForm.apiKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Models")
                    .font(.subheadline.weight(.medium))

                ForEach(editForm.models) { model in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 6) {
                            TextField("Model ID", text: editModelNameBinding(for: model.id))
                                .textFieldStyle(.roundedBorder)

                            TextField(
                                "Alias (optional)", text: editModelAliasBinding(for: model.id)
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        Button(role: .destructive) {
                            editForm.models.removeAll { $0.id == model.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .padding(.top, 7)
                    }
                }

                if !editForm.modelsAreValid {
                    Text("Each model needs a unique model ID.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    TextField("New model ID", text: $editForm.draftModelName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Alias", text: $editForm.draftModelAlias)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        addModelToEditedList()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!editForm.canAddDraftModel)
                }

                if !editForm.draftModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !editForm.canAddDraftModel
                {
                    Text("This model ID is already in the list.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("Cancel") {
                    cancelEditingEndpoint()
                }

                Spacer()

                Button("Save Changes") {
                    saveEditedEndpoint(endpoint)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!editForm.canSubmit(in: editContext(for: endpoint)))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Model Addition


    func startEditingEndpoint(_ endpoint: CustomEndpoint) {
        withAnimation {
            if editingEndpointID == endpoint.id {
                cancelEditingEndpoint()
                return
            }

            editingEndpointID = endpoint.id
            editForm = EndpointFormState(
                endpoint: endpoint,
                apiKey: modelStore.apiKey(for: endpoint.id) ?? ""
            )
        }
    }


    func cancelEditingEndpoint() {
        editingEndpointID = nil
        editForm = EndpointFormState()
    }


    func editModelNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { editForm.models.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                guard let index = editForm.models.firstIndex(where: { $0.id == id }) else { return }
                editForm.models[index].name = newValue
            }
        )
    }


    func editModelAliasBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { editForm.models.first(where: { $0.id == id })?.alias ?? "" },
            set: { newValue in
                guard let index = editForm.models.firstIndex(where: { $0.id == id }) else { return }
                editForm.models[index].alias = newValue.isEmpty ? nil : newValue
            }
        )
    }


    func addModelToEditedList() {
        editForm.addDraftModel()
    }


    func saveEditedEndpoint(_ endpoint: CustomEndpoint) {
        guard editForm.canSubmit(in: editContext(for: endpoint)),
            let normalizedURL = EndpointURLValidator.normalizedBaseURL(from: editForm.baseURL)
        else { return }

        let normalizedModels = editForm.models.map { model in
            let alias = model.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CustomModel(
                id: model.id,
                name: model.name.trimmingCharacters(in: .whitespacesAndNewlines),
                alias: alias.isEmpty ? nil : alias
            )
        }

        let updated = CustomEndpoint(
            id: endpoint.id,
            name: editForm.name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedURL,
            models: normalizedModels
        )

        do {
            try modelStore.saveAPIKey(editForm.apiKey, for: endpoint.id)
            modelStore.updateEndpoint(updated)

            if modelStore.selectedModel() == nil, let first = updated.models.first {
                modelStore.selectModel(
                    ModelSelection(
                        id: first.id,
                        displayName: first.displayName,
                        endpointID: updated.id,
                        modelName: first.name,
                        baseURL: updated.baseURL
                    )
                )
            }

            withAnimation {
                cancelEditingEndpoint()
            }
        } catch {
            print("Failed to save endpoint edits: \(error)")
            keychainErrorMessage = error.localizedDescription
        }
    }

}
