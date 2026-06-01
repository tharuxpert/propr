import Foundation
import SwiftUI

@MainActor
@Observable
final class ModelStore {
    static let shared = ModelStore()
    
    var customEndpoints: [CustomEndpoint] = [] {
        didSet {
            rebuildAvailableModels()
        }
    }
    
    var selectedModelID: UUID? {
        didSet {
            // Persisted via saveEndpoints() → ModelConfigStore (models.json)
            saveEndpoints()
        }
    }
    
    private(set) var allAvailableModels: [ModelSelection] = []
    
    private init() {
        // Load everything from models.json (JSON is now the only storage)
        let config = ModelConfigStore.shared.load()
        customEndpoints = config.customEndpoints
        selectedModelID = config.selectedModelID.flatMap { UUID(uuidString: $0) }
        
        rebuildAvailableModels()
    }
    
    // MARK: - Persistence (fully JSON via ModelConfigStore now)
    
    private func saveEndpoints() {
        var config = ModelConfigStore.shared.load()
        config.customEndpoints = customEndpoints
        config.selectedModelID = selectedModelID?.uuidString
        ModelConfigStore.shared.save(config)
    }
    
    // MARK: - Public API
    
    private func rebuildAvailableModels() {
        var models: [ModelSelection] = []
        
        for endpoint in customEndpoints {
            for model in endpoint.models {
                models.append(ModelSelection(
                    id: model.id,
                    displayName: model.displayName,
                    endpointID: endpoint.id,
                    modelName: model.name,
                    baseURL: endpoint.baseURL
                ))
            }
        }
        
        allAvailableModels = models
    }
    
    func selectedModel() -> ModelSelection? {
        guard let id = selectedModelID else { return nil }
        return allAvailableModels.first { $0.id == id }
    }
    
    func addEndpoint(_ endpoint: CustomEndpoint) {
        customEndpoints.append(endpoint)
        saveEndpoints()
    }
    
    func deleteEndpoint(id: UUID) {
        // Remove the key from our JSON config
        var config = ModelConfigStore.shared.load()
        config.apiKeys.removeValue(forKey: id.uuidString)
        ModelConfigStore.shared.save(config)
        
        customEndpoints.removeAll { $0.id == id }
        
        // If the selected model belonged to this endpoint, clear selection
        if let selected = selectedModel(), selected.endpointID == id {
            selectedModelID = nil
        }
        
        saveEndpoints()
    }
    
    func updateEndpoint(_ updated: CustomEndpoint) {
        if let index = customEndpoints.firstIndex(where: { $0.id == updated.id }) {
            customEndpoints[index] = updated
            saveEndpoints()
        }
    }
    
    func selectModel(_ model: ModelSelection) {
        selectedModelID = model.id
    }
    
    // Helper to get API key for an endpoint (from Keychain)
    func apiKey(for endpointID: UUID) -> String? {
        let config = ModelConfigStore.shared.load()
        return config.apiKeys[endpointID.uuidString]
    }
    
    func saveAPIKey(_ key: String, for endpointID: UUID) {
        var config = ModelConfigStore.shared.load()
        config.apiKeys[endpointID.uuidString] = key
        ModelConfigStore.shared.save(config)
    }
}

// Simple struct used for menu + selection
struct ModelSelection: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let endpointID: UUID
    let modelName: String      // The actual model identifier sent to the API
    let baseURL: String
}