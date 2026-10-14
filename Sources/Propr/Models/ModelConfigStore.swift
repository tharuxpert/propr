import Foundation

/// File-based storage for model configuration.
/// Stored at ~/Library/Application Support/Propr/models.json
/// Non-secret model configuration. API keys are never stored here — they live in
/// the Keychain (see `KeychainManager`).
struct ModelConfig: Codable {
    var customEndpoints: [CustomEndpoint] = []
    var selectedModelID: String?  // stored as string for JSON friendliness
    /// The model quick lookups use. Nil means the same as `selectedModelID`, and is
    /// also what files written before this existed decode to.
    var lookupModelID: String?
}

@MainActor
final class ModelConfigStore {
    static let shared = ModelConfigStore()

    private(set) var fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("Propr", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: appDir.path)
        self.fileURL = appDir.appendingPathComponent("models.json")
    }

    func load() -> ModelConfig {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ModelConfig()
        }
        do {
            return try JSONDecoder().decode(ModelConfig.self, from: data)
        } catch {
            print("[Propr] Failed to decode models.json: \(error)")
            return ModelConfig()
        }
    }

    func save(_ config: ModelConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            print("[Propr] Failed to save models.json: \(error)")
        }
    }

}
