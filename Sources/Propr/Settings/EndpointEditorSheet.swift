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
    @State private var catalog = ModelCatalogLoader()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, modelID
    }

    private var isEditing: Bool { endpoint != nil }

    private var context: EndpointFormState.ValidationContext {
        .init(existingEndpoints: existingEndpoints, excludingEndpointID: endpoint?.id)
    }

    /// Local endpoints (Ollama, LM Studio) do not need a key.
    private var requiresKey: Bool {
        EndpointURLValidator.requiresAPIKey(for: form.baseURL)
    }

    /// The catalog request carries the API key, so it is only offered once the URL is
    /// usable and, for a remote endpoint, a key is actually there to send.
    private var canLoadCatalog: Bool {
        form.urlError == nil && (!requiresKey || !form.trimmedAPIKey.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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

                    // Each field sits in LabeledContent with its own label hidden.
                    // Grouped forms otherwise right-align a labelled field's
                    // placeholder while typed text is left-aligned, which looks broken
                    // inside a bezel.
                    //
                    // Placeholders use Text(verbatim:). A plain string literal is a
                    // LocalizedStringKey, which SwiftUI parses as Markdown — and a bare
                    // URL gets autolinked, so the example URL rendered as a blue link
                    // that looked like an already-filled value.
                    LabeledContent("Name") {
                        TextField(
                            "Name", text: $form.name,
                            prompt: Text(verbatim: "e.g. My OpenRouter")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .focused($focusedField, equals: .name)
                    }
                    validationMessage(form.nameError(in: context))

                    LabeledContent("Base URL") {
                        TextField(
                            "Base URL", text: $form.baseURL,
                            prompt: Text(verbatim: "https://api.example.com/v1")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                    }
                    validationMessage(form.urlError)

                    if requiresKey {
                        LabeledContent("API Key") {
                            SecureField(
                                "API Key", text: $form.apiKey,
                                prompt: Text(verbatim: provider?.apiKeyExample ?? "Paste your key")
                            )
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                        }
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

                    // The provider's own catalog, so identifiers never have to be hunted
                    // down by hand. An explicit action rather than a fetch on open: the
                    // request sends the API key, so it must only ever go to a host the
                    // user has finished typing.
                    HStack(spacing: 8) {
                        Button("Load Models from Provider") {
                            // The trimmed key, matching what `save` persists: a key pasted
                            // with a trailing newline is a 401 on most providers.
                            catalog.load(baseURL: form.baseURL, apiKey: form.trimmedAPIKey)
                        }
                        .disabled(!canLoadCatalog || catalog.isFetching)

                        if catalog.isFetching {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer(minLength: 0)
                    }

                    if let error = catalog.error {
                        Text(error.errorDescription ?? "The model list could not be loaded.")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !catalog.ids.isEmpty {
                        ModelCatalogPicker(
                            ids: catalog.ids,
                            alreadyAdded: Set(form.models.map(\.name))
                        ) { names in
                            form.addModels(names: names)
                        }
                    }

                    // Two inputs share one row, so their labels are hidden and the
                    // placeholders carry the meaning — otherwise the grouped form turns
                    // the labels into what looked like column headings.
                    HStack(spacing: 8) {
                        TextField("Model ID", text: $form.draftModelName, prompt: Text(verbatim: "Model ID"))
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .focused($focusedField, equals: .modelID)
                            .onSubmit(addDraftModel)
                        TextField(
                            "Alias", text: $form.draftModelAlias, prompt: Text(verbatim: "Alias (optional)")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 150)
                        .onSubmit(addDraftModel)
                        // Distinct from the sheet's own "Add" button below.
                        Button("Add Model", action: addDraftModel)
                            .disabled(!form.canAddDraftModel)
                    }
                } header: {
                    Text("Models")
                } footer: {
                    Text(
                        "The model ID must match the provider exactly. An alias is what Propr shows in its menu. A provider's list is its whole catalog, so it can include models Propr cannot chat with, such as embeddings and speech models."
                    )
                }
            }
            .formStyle(.grouped)
            // Grouped forms draw text fields borderless and right-aligned, which is fine
            // for a value you glance at but hides where you are supposed to type.
            // A bezel and leading-aligned text make each field unmistakably an input.
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)

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
        .frame(width: 520, height: 540)
        .onAppear(perform: prefill)
        // Identifiers fetched from one host must never be addable to another, so a
        // change of base URL drops the catalog. The API key is deliberately not watched:
        // a model list belongs to the provider, not to the credentials that read it.
        .onChange(of: form.baseURL) { _, _ in catalog.reset() }
        // Dismissing mid-fetch must not leave a request carrying an API key in flight.
        .onDisappear { catalog.cancel() }
        // Start in the first field to type in, not on the provider picker, which
        // otherwise opens wearing a focus ring.
        .defaultFocus($focusedField, .name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(isEditing ? "Edit Provider" : "Add Provider")
                .font(.headline)
            Text("Any OpenAI-compatible API works.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    /// Adds the typed model and puts the cursor back in the ID field for the next one.
    private func addDraftModel() {
        guard form.canAddDraftModel else { return }
        form.addDraftModel()
        focusedField = .modelID
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
