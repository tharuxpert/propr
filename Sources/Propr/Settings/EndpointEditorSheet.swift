import SwiftUI

/// Add or edit an endpoint, presented as a sheet.
///
/// Replaces the two near-identical inline forms that used to expand inside the
/// settings scroll view. Quick Start and "bring your own key" were separate flows
/// doing the same job; here choosing a provider simply prefills the name and URL,
/// and "Custom…" leaves them blank.
struct EndpointEditorSheet: View {
    /// The endpoint being edited, or nil when adding.
    let endpoint: CustomEndpoint?
    let existingEndpoints: [CustomEndpoint]
    let initialAPIKey: String
    let onSave: (CustomEndpoint, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var form = EndpointFormState()
    @State private var provider: BuiltInProvider?
    @State private var didPrefill = false

    private var isEditing: Bool { endpoint != nil }

    private var context: EndpointFormState.ValidationContext {
        .init(existingEndpoints: existingEndpoints, excludingEndpointID: endpoint?.id)
    }

    /// Local endpoints (Ollama, LM Studio) do not need a key.
    private var requiresKey: Bool {
        EndpointURLValidator.requiresAPIKey(for: form.baseURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if !isEditing {
                        Picker("Provider", selection: $provider) {
                            Text("Custom…").tag(BuiltInProvider?.none)
                            Divider()
                            ForEach(BuiltInProvider.all) { candidate in
                                Text(candidate.name).tag(BuiltInProvider?.some(candidate))
                            }
                        }
                        .onChange(of: provider) { _, newValue in
                            apply(newValue)
                        }
                    }

                    TextField("Name", text: $form.name)
                    validationMessage(form.nameError(in: context))

                    TextField("Base URL", text: $form.baseURL, prompt: Text("https://…/v1"))
                    validationMessage(form.urlError)

                    if requiresKey {
                        SecureField(
                            "API Key", text: $form.apiKey,
                            prompt: Text(provider?.apiKeyExample ?? "sk-…"))
                        validationMessage(form.apiKeyError)
                    }
                } footer: {
                    if let provider, !isEditing {
                        Text(provider.description)
                    } else if !requiresKey && !form.baseURL.isEmpty {
                        Text("Local endpoints don't need an API key.")
                    }
                }

                Section {
                    ForEach(form.models) { model in
                        LabeledContent {
                            HStack(spacing: 8) {
                                if model.alias != nil {
                                    Text(model.name)
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                }
                                Button {
                                    form.removeModel(model)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Remove \(model.displayName)")
                            }
                        } label: {
                            Text(model.displayName)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Model ID", text: $form.draftModelName)
                        TextField("Alias (optional)", text: $form.draftModelAlias)
                        Button("Add") { form.addDraftModel() }
                            .disabled(!form.canAddDraftModel)
                    }
                } header: {
                    Text("Models")
                } footer: {
                    Text(
                        "The model ID must match the provider exactly. An alias is what Propr shows in its menu."
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canSubmit(in: context))
            }
            .padding(16)
        }
        .frame(width: 520, height: 520)
        .onAppear(perform: prefill)
    }

    /// Shows a rule only once it is actually violated, so the form is not shouting
    /// at the user before they have typed anything.
    @ViewBuilder
    private func validationMessage(_ message: String?) -> some View {
        if let message, !form.trimmedName.isEmpty || !form.trimmedBaseURL.isEmpty {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true

        if let endpoint {
            form = EndpointFormState(endpoint: endpoint, apiKey: initialAPIKey)
        }
    }

    private func apply(_ provider: BuiltInProvider?) {
        guard let provider else { return }
        form.name = provider.name
        form.baseURL = provider.baseURL
    }

    private func save() {
        guard let built = form.makeEndpoint(id: endpoint?.id ?? UUID(), in: context) else { return }
        onSave(built, form.apiKey)
        dismiss()
    }
}
