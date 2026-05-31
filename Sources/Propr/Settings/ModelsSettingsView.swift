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
        VStack(alignment: .leading, spacing: 24) {
            Text("Models")
                .font(.title2.weight(.semibold))
            
            // Quick Start (Built-in providers)
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
            
            // Quick Add Form (appears when a provider is selected)
            if let provider = quickAddProvider {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add \(provider.name)")
                        .font(.headline)
                    
                    if provider.requiresKey {
                        SecureField("API Key", text: $quickAddAPIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text("No API key required for local models.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Button("Cancel") {
                            quickAddProvider = nil
                            quickAddAPIKey = ""
                        }
                        
                        Spacer()
                        
                        Button("Add \(provider.name)") {
                            addQuickProvider()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(provider.requiresKey && quickAddAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            // Full Custom Endpoint
            VStack(alignment: .leading, spacing: 12) {
                Text("Bring Your Own Key (BYOK)")
                    .font(.headline)
                
                Text("Add any OpenAI-compatible endpoint manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingAddForm.toggle()
                        if !showingAddForm {
                            resetAddForm()
                        }
                    }
                } label: {
                    Label("Add custom endpoint", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                
                // Inline add form (smoothly appears)
                if showingAddForm {
                    addEndpointForm
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .padding(.top, 8)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            // Existing custom endpoints
            if !modelStore.customEndpoints.isEmpty {
                Text("Your Endpoints")
                    .font(.headline)
                
                ForEach(modelStore.customEndpoints) { endpoint in
                    endpointRow(endpoint)
                }
            } else if !showingAddForm {
                ContentUnavailableView(
                    "No custom endpoints yet",
                    systemImage: "network",
                    description: Text("Add your first OpenAI-compatible endpoint above.")
                )
            }
            
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }
    
    private var addEndpointForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Endpoint")
                .font(.headline)
            
            TextField("Endpoint name", text: $endpointName)
                .textFieldStyle(.roundedBorder)
            
            TextField("Endpoint URL (e.g. https://api.groq.com/openai/v1)", text: $endpointURL)
                .textFieldStyle(.roundedBorder)
            
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            
            Divider()
            
            Text("Models from this endpoint")
                .font(.subheadline.weight(.medium))
            
            HStack {
                TextField("Model name (e.g. llama-3.1-70b)", text: $newModelName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Alias (optional)", text: $newModelAlias)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    addModelToList()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            if !addedModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(addedModels) { model in
                        HStack {
                            Text(model.displayName)
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
    
    private var canAddEndpoint: Bool {
        !endpointName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !endpointURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !addedModels.isEmpty
    }
    
    private func addModelToList() {
        let trimmedName = newModelName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let alias = newModelAlias.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newModelAlias.trimmingCharacters(in: .whitespaces)
        
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
        
        let endpoint = CustomEndpoint(
            name: endpointName.trimmingCharacters(in: .whitespaces),
            baseURL: endpointURL.trimmingCharacters(in: .whitespaces),
            models: addedModels
        )
        
        // Save the API key securely
        do {
            try modelStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces), for: endpoint.id)
            modelStore.addEndpoint(endpoint)
            
            // Reset form
            resetAddForm()
            showingAddForm = false
            
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
    }
    
    private func addQuickProvider() {
        guard let provider = quickAddProvider,
              !quickAddAPIKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let models = provider.defaultModels.map { CustomModel(name: $0) }
        
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
            
            // Reset
            quickAddProvider = nil
            quickAddAPIKey = ""
            
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
                Text("• \(model.displayName)")
                    .font(.caption)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    ModelsSettingsView()
}