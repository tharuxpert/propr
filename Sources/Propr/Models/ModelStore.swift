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
    /// otherwise the refine model.
    func lookupModel() -> ModelSelection? {
        Self.resolveLookupModel(
            lookupID: lookupModelID, refineModel: selectedModel(), available: allAvailableModels)
    }

    nonisolated static func resolveLookupModel(
        lookupID: UUID?, refineModel: ModelSelection?, available: [ModelSelection]
    ) -> ModelSelection? {
        guard let lookupID, let model = available.first(where: { $0.id == lookupID }) else {
            return refineModel
        }
        return model
    }

    /// The nil choice in both Lookup Model surfaces. A lookup with no override follows the
    /// refine model, so it is deliberately not called a default.
    ///
    /// Defined once because it is shown in two places — the Settings picker and the menu
    /// bar submenu — and the last rename reached only one of them. `nonisolated` so the
    /// menu-building function below, and the tests, can read it without the actor.
    nonisolated static let sameAsRefineModelTitle = "Same as Refine Model"

    /// The Lookup Model menu, in the order it is shown: the "Same as Refine Model" choice
    /// first, then every configured model. Kept free of AppKit so it stays testable.
    nonisolated static func lookupModelMenuItems(
        lookupID: UUID?, available: [ModelSelection]
    ) -> [LookupModelMenuItem] {
        var items = [
            LookupModelMenuItem(
                modelID: nil, title: Self.sameAsRefineModelTitle, isSelected: lookupID == nil)
        ]
        items += available.map {
            LookupModelMenuItem(modelID: $0.id, title: $0.displayName, isSelected: $0.id == lookupID)
        }
        return items
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

/// One row of the Lookup Model menu. `modelID == nil` is the "Same as Refine Model" row.
struct LookupModelMenuItem: Equatable {
    let modelID: UUID?
    let title: String
    let isSelected: Bool
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
