import Foundation
import Testing

@testable import Propr

/// Quick lookups can use their own model. These pin down when that choice applies
/// and that older saved configurations still load.
struct LookupModelTests {
    private func model(_ name: String) -> ModelSelection {
        ModelSelection(
            id: UUID(), displayName: name, endpointID: UUID(), modelName: name,
            baseURL: "https://api.example.com/v1")
    }

    @Test("A chosen lookup model is used while it exists")
    func chosenModel() {
        let fast = model("fast"), strong = model("strong")
        let resolved = ModelStore.resolveLookupModel(
            lookupID: fast.id, defaultModel: strong, available: [fast, strong])
        #expect(resolved == fast)
    }

    @Test("Same as Default, or a deleted lookup model, falls back to the default")
    func fallsBackToDefault() {
        let strong = model("strong")
        #expect(
            ModelStore.resolveLookupModel(lookupID: nil, defaultModel: strong, available: [strong])
                == strong)
        #expect(
            ModelStore.resolveLookupModel(lookupID: UUID(), defaultModel: strong, available: [strong])
                == strong)
    }

    @Test("A models.json written before lookup models existed still loads")
    func oldConfigDecodes() throws {
        let id = UUID().uuidString
        let json = #"{"customEndpoints":[],"selectedModelID":"\#(id)"}"#
        let config = try JSONDecoder().decode(ModelConfig.self, from: Data(json.utf8))
        #expect(config.selectedModelID == id)
        #expect(config.lookupModelID == nil)
    }
}
