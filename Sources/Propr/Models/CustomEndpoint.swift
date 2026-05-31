import Foundation

struct CustomModel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String          // e.g. "glm-4-flash"
    var alias: String?        // e.g. "GLM-4 Flash" (user-friendly name shown in picker)

    init(id: UUID = UUID(), name: String, alias: String? = nil) {
        self.id = id
        self.name = name
        self.alias = alias
    }

    var displayName: String {
        alias ?? name
    }
}

struct CustomEndpoint: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String                    // User-given name for the endpoint (e.g. "My Groq")
    var baseURL: String                 // Must be a valid base, e.g. "https://api.groq.com/openai/v1"
    var models: [CustomModel]           // One or more models from this endpoint

    init(id: UUID = UUID(), name: String, baseURL: String, models: [CustomModel] = []) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
    }

    // Helper for display in menus
    var displayName: String { name }
}