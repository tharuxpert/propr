import Foundation
import SwiftUI

extension Notification.Name {
    static let proprModelStoreDidChange = Notification.Name("proprModelStoreDidChange")
}

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
            notifyChanged()
        }
    }

    /// The model quick lookups use instead of the default; nil follows the default.
    var lookupModelID: UUID? {
        didSet {
            saveEndpoints()
            notifyChanged()
        }
    }

    private(set) var allAvailableModels: [ModelSelection] = []

    private init() {
        // Endpoints and selection live in models.json; API keys live in the Keychain.
        let config = ModelConfigStore.shared.load()
        customEndpoints = config.customEndpoints
        selectedModelID = config.selectedModelID.flatMap { UUID(uuidString: $0) }
        lookupModelID = config.lookupModelID.flatMap { UUID(uuidString: $0) }

        rebuildAvailableModels()
    }

    // MARK: - Persistence (fully JSON via ModelConfigStore now)

    private func saveEndpoints() {
        var config = ModelConfigStore.shared.load()
        config.customEndpoints = customEndpoints
        config.selectedModelID = selectedModelID?.uuidString
        config.lookupModelID = lookupModelID?.uuidString
        ModelConfigStore.shared.save(config)
    }

    // MARK: - Public API

    private func rebuildAvailableModels() {
        var models: [ModelSelection] = []

        for endpoint in customEndpoints {
            for model in endpoint.models {
                models.append(
                    ModelSelection(
                        id: model.id,
                        displayName: model.displayName,
                        endpointID: endpoint.id,
                        modelName: model.name,
                        baseURL: endpoint.baseURL
                    ))
            }
        }

        allAvailableModels = models
        notifyChanged()
    }

    func selectedModel() -> ModelSelection? {
        guard let id = selectedModelID else { return nil }
        return allAvailableModels.first { $0.id == id }
    }

    /// The model quick lookups use: the chosen lookup model while it still exists,
    /// otherwise the default model.
    func lookupModel() -> ModelSelection? {
        Self.resolveLookupModel(
            lookupID: lookupModelID, defaultModel: selectedModel(), available: allAvailableModels)
    }

    nonisolated static func resolveLookupModel(
        lookupID: UUID?, defaultModel: ModelSelection?, available: [ModelSelection]
    ) -> ModelSelection? {
        guard let lookupID, let model = available.first(where: { $0.id == lookupID }) else {
            return defaultModel
        }
        return model
    }

    func addEndpoint(_ endpoint: CustomEndpoint) {
        customEndpoints.append(endpoint)
        saveEndpoints()
    }

    func deleteEndpoint(id: UUID) {
        KeychainManager.shared.deleteAPIKey(for: id)

        customEndpoints.removeAll { $0.id == id }

        // If the selected model belonged to this endpoint, clear selection
        if let selected = selectedModel(), selected.endpointID == id {
            selectedModelID = nil
        }
        if let lookupModelID, !allAvailableModels.contains(where: { $0.id == lookupModelID }) {
            self.lookupModelID = nil
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

    func apiKey(for endpointID: UUID) -> String? {
        do {
            return try KeychainManager.shared.apiKey(for: endpointID)
        } catch {
            print("[Propr] Keychain read failed for endpoint \(endpointID): \(error)")
            return nil
        }
    }

    func saveAPIKey(_ key: String, for endpointID: UUID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            KeychainManager.shared.deleteAPIKey(for: endpointID)
        } else {
            try KeychainManager.shared.saveAPIKey(trimmed, for: endpointID)
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .proprModelStoreDidChange, object: self)
    }
}

// Simple struct used for menu + selection
struct ModelSelection: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let endpointID: UUID
    let modelName: String  // The actual model identifier sent to the API
    let baseURL: String

    var requiresAPIKey: Bool {
        EndpointURLValidator.requiresAPIKey(for: baseURL)
    }
}
