import SwiftUI

struct ModelsSettingsView: View {
    @State private var modelStore = ModelStore.shared

    @State private var showingAddForm = false

    // Quick Add state
    @State private var quickAddProvider: BuiltInProvider?
    @State private var quickAddAPIKey = ""
    @State private var quickAddBaseURL = ""  // editable for Local provider (Ollama/LM Studio etc.)

    // Form state for adding new endpoint (full custom)
    @State private var endpointName = ""
    @State private var endpointURL = ""
    @State private var apiKey = ""
    @State private var newModelName = ""
    @State private var newModelAlias = ""
    @State private var addedModels: [CustomModel] = []

    // Edit endpoint state
    @State private var editingEndpointID: UUID?
    @State private var editEndpointName = ""
    @State private var editEndpointURL = ""
    @State private var editAPIKey = ""
    @State private var editModels: [CustomModel] = []
    @State private var editNewModelName = ""
    @State private var editNewModelAlias = ""

    /// Set when a Keychain write fails, so the user is told instead of the
    /// failure being swallowed into a console log.
    @State private var keychainErrorMessage: String?

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Removed the "Models" title here — the TabView tab already labels this section,
                    // and having it caused ugly double-labeling + truncation near the window title bar.

                    // Quick Start (Built-in providers)
                    // Non-lazy grid to avoid cells disappearing during fast scroll when the
                    // quick-add form below is open (LazyVGrid + dynamic content height change
                    // below it is a known source of recycling glitches).
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Start")
                            .font(.headline)

                        Text("Popular providers — just paste your API key.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Stable non-lazy rows (8 providers → max 3 per row). Eliminates the
                        // fast-scroll disappearance bug while the quick-add form is visible.
                        let providers = BuiltInProvider.all
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(stride(from: 0, to: providers.count, by: 3)), id: \.self)
                            {
                                start in
                                HStack(spacing: 10) {
                                    ForEach(0..<3, id: \.self) { offset in
                                        let index = start + offset
                                        if index < providers.count {
                                            quickStartCard(for: providers[index])
                                        } else {
                                            Spacer()
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .animation(nil, value: showingAddForm)
                    .animation(nil, value: quickAddProvider != nil)

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
                                        text: $newModelName
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
                                        text: $newModelAlias
                                    )
                                    .textFieldStyle(.roundedBorder)

                                    Button {
                                        addModelToList()
                                    } label: {
                                        Label("Add model", systemImage: "plus.circle.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(
                                        newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }

                                if !addedModels.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Models to add")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        ForEach(addedModels) { model in
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
                                        addedModels = []
                                        newModelName = ""
                                        newModelAlias = ""
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
                                                    || normalizedEndpointURL(quickAddBaseURL) == nil))
                                            || addedModels.isEmpty
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

                    // Custom Endpoint (BYOK)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bring Your Own Key (BYOK)")
                            .font(.headline)

                        Button {
                            showingAddForm.toggle()
                            if !showingAddForm {
                                resetAddForm()
                            }
                        } label: {
                            Label("Add custom endpoint", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        // Inline add form (smoothly appears)
                        // We scope the animation to *this* VStack only so the Quick Start
                        // cards above don't get unwanted layout animation when the form expands.
                        if showingAddForm {
                            addEndpointForm
                                // Use scale from the top instead of .move(edge: .top) so the form
                                // expands downward in place and never visually flies in from above
                                // the BYOK section (avoiding overlap on Quick Start cards).
                                .transition(
                                    .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                )
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingAddForm)

                    // Existing custom endpoints
                    if !modelStore.customEndpoints.isEmpty {
                        Text("Your Endpoints")
                            .font(.headline)

                        ForEach(modelStore.customEndpoints) { endpoint in
                            endpointRow(endpoint)

                            if editingEndpointID == endpoint.id {
                                editEndpointForm(for: endpoint)
                                    .transition(
                                        .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

                                Color.clear
                                    .frame(height: 1)
                                    .id(editFormID(for: endpoint.id))
                                    .onAppear {
                                        scrollToEditForm(endpoint.id, with: scrollProxy)
                                    }
                            }
                        }
                    } else if !showingAddForm {
                        Spacer()

                        VStack(spacing: 16) {
                            Image(systemName: "network")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)

                            Text("No custom endpoints yet")
                                .font(.headline)

                            Text("Add your first OpenAI-compatible endpoint above.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .onChange(of: editingEndpointID) { _, endpointID in
                guard let endpointID else { return }
                scrollToEditForm(endpointID, with: scrollProxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 520)
        .alert(
            "Could not save the API key",
            isPresented: Binding(
                get: { keychainErrorMessage != nil },
                set: { if !$0 { keychainErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { keychainErrorMessage = nil }
        } message: {
            // Keys go to the Keychain, where a save can genuinely fail (locked
            // keychain, denied access). Failing silently would leave the endpoint
            // looking configured while refining reports a missing key.
            Text(keychainErrorMessage ?? "")
        }
    }

    private func editFormID(for endpointID: UUID) -> String {
        "edit-endpoint-\(endpointID.uuidString)"
    }

    private func scrollToEditForm(_ endpointID: UUID, with proxy: ScrollViewProxy) {
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

    private var addEndpointForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Endpoint name", text: $endpointName)
                .textFieldStyle(.roundedBorder)
            if let error = endpointNameError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Endpoint URL (e.g. https://api.groq.com/openai/v1)", text: $endpointURL)
                .textFieldStyle(.roundedBorder)
            if let error = endpointURLError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("API Key (e.g. sk-...)", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            if let error = apiKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("Models")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 6) {
                TextField("Model ID (e.g. anthropic/claude-3-5-sonnet)", text: $newModelName)
                    .textFieldStyle(.roundedBorder)

                TextField("Alias (shown in menu, optional)", text: $newModelAlias)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addModelToList()
                } label: {
                    Label("Add model", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(!canAddCurrentModel())

                // Show duplicate error if user is trying to add something invalid
                if !newModelName.trimmingCharacters(in: .whitespaces).isEmpty
                    && !canAddCurrentModel()
                {
                    Text("This model (or alias) is already in the list")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !addedModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addedModels) { model in
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
                        addedModels = []
                        newModelName = ""
                        newModelAlias = ""
                    }
                }

                Spacer()

                Button("Add Endpoint") {
                    addEndpoint()
                }
                .disabled(!canAddEndpoint)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func editEndpointForm(for endpoint: CustomEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(endpoint.name)")
                .font(.headline)

            TextField("Endpoint name", text: $editEndpointName)
                .textFieldStyle(.roundedBorder)
            if let error = editEndpointNameError(for: endpoint) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Endpoint URL", text: $editEndpointURL)
                .textFieldStyle(.roundedBorder)
            if let error = editEndpointURLError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("API Key", text: $editAPIKey)
                .textFieldStyle(.roundedBorder)
            if let error = editAPIKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Models")
                    .font(.subheadline.weight(.medium))

                ForEach(editModels) { model in
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
                            editModels.removeAll { $0.id == model.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .padding(.top, 7)
                    }
                }

                if !editModelsAreValid {
                    Text("Each model needs a unique model ID.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    TextField("New model ID", text: $editNewModelName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Alias", text: $editNewModelAlias)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        addModelToEditedList()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canAddEditedModel)
                }

                if !editNewModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !canAddEditedModel
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
                .disabled(!canSaveEditedEndpoint(for: endpoint))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Validation Helpers

    private func normalizedEndpointURL(_ string: String) -> String? {
        EndpointURLValidator.normalizedBaseURL(from: string)
    }

    private var endpointNameError: String? {
        let name = endpointName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Endpoint name is required"
        }
        // Check for duplicate names (case insensitive)
        if modelStore.customEndpoints.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "An endpoint with this name already exists"
        }
        return nil
    }

    private var endpointURLError: String? {
        let url = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            return "Endpoint URL is required"
        }
        if normalizedEndpointURL(url) == nil {
            return "Use HTTPS for remote providers, or HTTP for localhost."
        }
        return nil
    }

    private var apiKeyError: String? {
        guard endpointURLError == nil,
            EndpointURLValidator.requiresAPIKey(for: endpointURL),
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return "API key is required for remote endpoints."
    }

    private func editEndpointNameError(for endpoint: CustomEndpoint) -> String? {
        let name = editEndpointName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Endpoint name is required"
        }
        if modelStore.customEndpoints.contains(where: {
            $0.id != endpoint.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return "An endpoint with this name already exists"
        }
        return nil
    }

    private var editEndpointURLError: String? {
        let url = editEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            return "Endpoint URL is required"
        }
        if normalizedEndpointURL(url) == nil {
            return "Use HTTPS for remote providers, or HTTP for localhost."
        }
        return nil
    }

    private var editAPIKeyError: String? {
        guard editEndpointURLError == nil,
            EndpointURLValidator.requiresAPIKey(for: editEndpointURL),
            editAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return "API key is required for remote endpoints."
    }

    private var editModelsAreValid: Bool {
        let trimmedNames = editModels.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmedNames.isEmpty, trimmedNames.allSatisfy({ !$0.isEmpty }) else { return false }
        return Set(trimmedNames).count == trimmedNames.count
    }

    private var canAddEditedModel: Bool {
        let name = editNewModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return !editModels.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
        }
    }

    private func canSaveEditedEndpoint(for endpoint: CustomEndpoint) -> Bool {
        editEndpointNameError(for: endpoint) == nil
            && editEndpointURLError == nil
            && editAPIKeyError == nil
            && editModelsAreValid
    }

    private var canAddEndpoint: Bool {
        endpointNameError == nil && endpointURLError == nil && apiKeyError == nil
            && !addedModels.isEmpty
    }

    private func canAddCurrentModel() -> Bool {
        let name = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        // Check for duplicate model name within current list (case sensitive, as model IDs usually are)
        if addedModels.contains(where: { $0.name == name }) {
            return false
        }

        // Check alias doesn't conflict with existing display names in this list
        let alias = newModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alias.isEmpty {
            if addedModels.contains(where: {
                $0.displayName.caseInsensitiveCompare(alias) == .orderedSame
            }) {
                return false
            }
            // Also don't let alias match another model's raw name
            if addedModels.contains(where: { $0.name.caseInsensitiveCompare(alias) == .orderedSame }
            ) {
                return false
            }
        }

        return true
    }

    // MARK: - Model Addition

    private func addModelToList() {
        guard canAddCurrentModel() else { return }

        let trimmedName = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias =
            newModelAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : newModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)

        let model = CustomModel(name: trimmedName, alias: alias)
        addedModels.append(model)

        newModelName = ""
        newModelAlias = ""
    }

    private func removeModelFromList(_ model: CustomModel) {
        addedModels.removeAll { $0.id == model.id }
    }

    private func addEndpoint() {
        guard canAddEndpoint else { return }

        guard let normalizedURL = normalizedEndpointURL(endpointURL) else { return }

        let endpoint = CustomEndpoint(
            name: endpointName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedURL,
            models: addedModels
        )

        do {
            try modelStore.saveAPIKey(apiKey, for: endpoint.id)
            modelStore.addEndpoint(endpoint)

            // Reset form + model picker state
            resetAddForm()
            showingAddForm = false
            addedModels = []
            newModelName = ""
            newModelAlias = ""

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

    private func startQuickAdd(for provider: BuiltInProvider) {
        quickAddProvider = provider
        quickAddAPIKey = ""
        quickAddBaseURL = provider.baseURL  // prefill with the provider's default (user can edit for Local)

        // Start empty so the user manually adds exactly the models they want
        // (with aliases), same as the custom BYOK flow.
        addedModels = []
    }

    private func addQuickProvider() {
        guard let provider = quickAddProvider else { return }

        let trimmedKey = quickAddAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = quickAddBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // For local providers we don't require a key, but we do require a valid base URL
        if provider.requiresKey && trimmedKey.isEmpty { return }
        guard let normalizedURL = normalizedEndpointURL(trimmedURL) else { return }

        // Use whatever models + aliases the user curated in the list (same as custom endpoint flow)
        let models = addedModels

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
            addedModels = []
            newModelName = ""
            newModelAlias = ""

        } catch {
            print("Failed to save API key for quick provider: \(error)")
            keychainErrorMessage = error.localizedDescription
        }
    }

    private func resetAddForm() {
        endpointName = ""
        endpointURL = ""
        apiKey = ""
        newModelName = ""
        newModelAlias = ""
        addedModels = []
        quickAddBaseURL = ""
    }

    private func startEditingEndpoint(_ endpoint: CustomEndpoint) {
        withAnimation {
            if editingEndpointID == endpoint.id {
                cancelEditingEndpoint()
                return
            }

            editingEndpointID = endpoint.id
            editEndpointName = endpoint.name
            editEndpointURL = endpoint.baseURL
            editAPIKey = modelStore.apiKey(for: endpoint.id) ?? ""
            editModels = endpoint.models
            editNewModelName = ""
            editNewModelAlias = ""
        }
    }

    private func cancelEditingEndpoint() {
        editingEndpointID = nil
        editEndpointName = ""
        editEndpointURL = ""
        editAPIKey = ""
        editModels = []
        editNewModelName = ""
        editNewModelAlias = ""
    }

    private func editModelNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { editModels.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                guard let index = editModels.firstIndex(where: { $0.id == id }) else { return }
                editModels[index].name = newValue
            }
        )
    }

    private func editModelAliasBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { editModels.first(where: { $0.id == id })?.alias ?? "" },
            set: { newValue in
                guard let index = editModels.firstIndex(where: { $0.id == id }) else { return }
                editModels[index].alias = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func addModelToEditedList() {
        guard canAddEditedModel else { return }

        let name = editNewModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = editNewModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        editModels.append(CustomModel(name: name, alias: alias.isEmpty ? nil : alias))
        editNewModelName = ""
        editNewModelAlias = ""
    }

    private func saveEditedEndpoint(_ endpoint: CustomEndpoint) {
        guard canSaveEditedEndpoint(for: endpoint),
            let normalizedURL = normalizedEndpointURL(editEndpointURL)
        else { return }

        let normalizedModels = editModels.map { model in
            let alias = model.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CustomModel(
                id: model.id,
                name: model.name.trimmingCharacters(in: .whitespacesAndNewlines),
                alias: alias.isEmpty ? nil : alias
            )
        }

        let updated = CustomEndpoint(
            id: endpoint.id,
            name: editEndpointName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedURL,
            models: normalizedModels
        )

        do {
            try modelStore.saveAPIKey(editAPIKey, for: endpoint.id)
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

    private func endpointRow(_ endpoint: CustomEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(endpoint.name)
                    .font(.headline)

                Spacer()

                Button {
                    startEditingEndpoint(endpoint)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Button(role: .destructive) {
                    if editingEndpointID == endpoint.id {
                        cancelEditingEndpoint()
                    }
                    modelStore.deleteEndpoint(id: endpoint.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Text(endpoint.baseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            ForEach(endpoint.models) { model in
                if let alias = model.alias {
                    HStack(spacing: 4) {
                        Text("• \(alias)")
                            .font(.caption)
                        Text("(\(model.name))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("• \(model.name)")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // Small stable card used in the non-lazy Quick Start grid.
    // Extracted so the row layout code above stays readable.
    private func quickStartCard(for provider: BuiltInProvider) -> some View {
        Button {
            startQuickAdd(for: provider)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.subheadline.weight(.medium))
                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelsSettingsView()
}
