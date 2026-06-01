import SwiftUI

struct ModelsSettingsView: View {
    @State private var modelStore = ModelStore.shared
    
    @State private var showingAddForm = false
    
    // Quick Add state
    @State private var quickAddProvider: BuiltInProvider?
    @State private var quickAddAPIKey = ""
    
    // Form state for adding new endpoint (full custom)
    @State private var endpointName = ""
    @State private var endpointURL = ""
    @State private var apiKey = ""
    @State private var newModelName = ""
    @State private var newModelAlias = ""
    @State private var addedModels: [CustomModel] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
            // Removed the "Models" title here — the TabView tab already labels this section,
            // and having it caused ugly double-labeling + truncation near the window title bar.
            
            // Quick Start (Built-in providers)
            // Explicitly disable animation from the BYOK form toggle below so the
            // provider cards don't slide around when you expand/collapse the form.
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Start")
                    .font(.headline)
                
                Text("Popular providers — just paste your API key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(BuiltInProvider.all) { provider in
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
                            SecureField(provider.apiKeyExample ?? "API Key", text: $quickAddAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text("No API key required for local models.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Same model + alias picker as custom BYOK
                        Divider()
                        
                        Text("Models to include")
                            .font(.subheadline.weight(.medium))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Model ID (exact string sent to the API)", text: $newModelName)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Alias (optional – what shows in Propr’s menu)", text: $newModelAlias)
                                .textFieldStyle(.roundedBorder)
                            
                            Button {
                                addModelToList()
                            } label: {
                                Label("Add model", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
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
                                                .fontWeight(model.alias != nil ? .medium : .regular)
                                            
                                            if let alias = model.alias {
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
                                addedModels = []
                                newModelName = ""
                                newModelAlias = ""
                            }
                            
                            Spacer()
                            
                            Button("Add \(provider.name)") {
                                addQuickProvider()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled( (provider.requiresKey && quickAddAPIKey.trimmingCharacters(in: .whitespaces).isEmpty) || addedModels.isEmpty )
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: quickAddProvider != nil)
            
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
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .frame(minWidth: 520)
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
                if !newModelName.trimmingCharacters(in: .whitespaces).isEmpty && !canAddCurrentModel() {
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
                                
                                if let alias = model.alias {
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
    
    // MARK: - Validation Helpers

    private func isValidEndpointURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }

    private var endpointNameError: String? {
        let name = endpointName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Endpoint name is required"
        }
        // Check for duplicate names (case insensitive)
        if modelStore.customEndpoints.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "An endpoint with this name already exists"
        }
        return nil
    }

    private var endpointURLError: String? {
        let url = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            return "Endpoint URL is required"
        }
        if !isValidEndpointURL(url) {
            return "Please enter a valid URL (e.g. https://api.openai.com/v1)"
        }
        return nil
    }

    private var apiKeyError: String? {
        // API key is required for most providers, but some local setups allow empty
        // For custom endpoints we treat it as required (user can leave empty for local if they want)
        return nil // We'll let it be optional for maximum flexibility
    }

    private var canAddEndpoint: Bool {
        endpointNameError == nil &&
        endpointURLError == nil &&
        !addedModels.isEmpty
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
            if addedModels.contains(where: { $0.displayName.caseInsensitiveCompare(alias) == .orderedSame }) {
                return false
            }
            // Also don't let alias match another model's raw name
            if addedModels.contains(where: { $0.name.caseInsensitiveCompare(alias) == .orderedSame }) {
                return false
            }
        }

        return true
    }

    // MARK: - Model Addition

    private func addModelToList() {
        guard canAddCurrentModel() else { return }

        let trimmedName = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = newModelAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)

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
        
        // Normalize URL (remove trailing slashes)
        var normalizedURL = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedURL.hasSuffix("/") {
            normalizedURL.removeLast()
        }

        let endpoint = CustomEndpoint(
            name: endpointName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedURL,
            models: addedModels
        )
        
        // Save the API key securely
        do {
            try modelStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: endpoint.id)
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
            // In real app, show proper error
            print("Failed to save API key: \(error)")
        }
    }
    
    private func startQuickAdd(for provider: BuiltInProvider) {
        quickAddProvider = provider
        quickAddAPIKey = ""
        
        // Start empty so the user manually adds exactly the models they want
        // (with aliases), same as the custom BYOK flow.
        addedModels = []
    }
    
    private func addQuickProvider() {
        guard let provider = quickAddProvider,
              !quickAddAPIKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Use whatever models + aliases the user curated in the list (same as custom endpoint flow)
        let models = addedModels
        
        let endpoint = CustomEndpoint(
            name: provider.name,
            baseURL: provider.baseURL,
            models: models
        )
        
        do {
            if provider.requiresKey {
                try modelStore.saveAPIKey(quickAddAPIKey.trimmingCharacters(in: .whitespaces), for: endpoint.id)
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
            addedModels = []
            newModelName = ""
            newModelAlias = ""
            
        } catch {
            print("Failed to save API key for quick provider: \(error)")
        }
    }
    
    private func resetAddForm() {
        endpointName = ""
        endpointURL = ""
        apiKey = ""
        newModelName = ""
        newModelAlias = ""
        addedModels = []
    }
    
    private func endpointRow(_ endpoint: CustomEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(endpoint.name)
                    .font(.headline)
                
                Spacer()
                
                Button(role: .destructive) {
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
}

#Preview {
    ModelsSettingsView()
}