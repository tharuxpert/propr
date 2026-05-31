import Foundation
import SwiftUI

@MainActor
@Observable
final class ModelStore {
    static let shared = ModelStore()
    
    private let endpointsKey = "customEndpoints"
    private let selectedModelKey = "selectedModelID"
    
    var customEndpoints: [CustomEndpoint] = [] {
        didSet {
            rebuildAvailableModels()
        }
    }
    
    var selectedModelID: UUID? {
        didSet {
            if let id = selectedModelID {
                UserDefaults.standard.set(id.uuidString, forKey: selectedModelKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedModelKey)
            }
        }
    }
    
    private(set) var allAvailableModels: [ModelSelection] = []
    
    private init() {
        loadEndpoints()
        loadSelectedModel()
        rebuildAvailableModels()
    }
    
    // MARK: - Persistence
    
    private func loadEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: endpointsKey) else { return }
        do {
            customEndpoints = try JSONDecoder().decode([CustomEndpoint].self, from: data)
        } catch {
            print("Failed to load custom endpoints: \(error)")
        }
    }
    
    private func saveEndpoints() {
        do {
            let data = try JSONEncoder().encode(customEndpoints)
            UserDefaults.standard.set(data, forKey: endpointsKey)
        } catch {
            print("Failed to save custom endpoints: \(error)")
        }
    }
    
    private func loadSelectedModel() {
        if let uuidString = UserDefaults.standard.string(forKey: selectedModelKey),
           let uuid = UUID(uuidString: uuidString) {
            selectedModelID = uuid
        }
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
        // Also delete the API key from Keychain
        KeychainManager.shared.deleteAPIKey(for: id)
        
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
    func apiKey(for endpointID: UUID) throws -> String? {
        try KeychainManager.shared.apiKey(for: endpointID)
    }
    
    func saveAPIKey(_ key: String, for endpointID: UUID) throws {
        try KeychainManager.shared.saveAPIKey(key, for: endpointID)
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