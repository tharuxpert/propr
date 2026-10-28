import Foundation
import Testing

@testable import Propr

/// Pins how a provider's model catalog is requested and read.
///
/// The catalog is the one place Propr trusts a provider to name its own models, so these
/// tests cover the two failures that would be quiet rather than loud: an identifier that
/// is not a usable `model` value reaching the list, and a provider that publishes no
/// catalog being reported as one with an empty catalog.
struct ModelCatalogTests {

    // MARK: - Reading the reply

    @Test("Model identifiers are read from the OpenAI data shape")
    func readsIdentifiers() {
        let body = #"{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"gpt-4o-mini"}]}"#
        #expect(ModelCatalogResponse.modelIDs(from: Data(body.utf8)) == ["gpt-4o", "gpt-4o-mini"])
    }

    @Test("Extra entry fields are ignored, including nested metadata")
    func ignoresMetadata() {
        // Shaped like a real OpenRouter entry: 465 of these arrived in one 778 KB reply.
        let body = """
            {"data":[{"id":"moondream/moondream3-preview","name":"Moondream 3",
            "context_length":32768,"pricing":{"prompt":"0.0000002"},
            "architecture":{"input_modalities":["image"]},
            "supported_parameters":["temperature"],"expiration_date":null}]}
            """
        #expect(
            ModelCatalogResponse.modelIDs(from: Data(body.utf8))
                == ["moondream/moondream3-preview"])
    }

    @Test("A provider with no catalog reads as unrecognised, not as empty")
    func unrecognisedShapes() {
        // Ollama's native /api/tags names models differently from the identifiers its
        // chat/completions route accepts, so it must not be read as a usable catalog.
        #expect(
            ModelCatalogResponse.modelIDs(from: Data(#"{"models":[{"name":"llama3.2:latest"}]}"#.utf8))
                == nil)
        #expect(ModelCatalogResponse.modelIDs(from: Data("<html>nope</html>".utf8)) == nil)
        #expect(ModelCatalogResponse.modelIDs(from: Data(#"{"data":null}"#.utf8)) == nil)
        #expect(ModelCatalogResponse.modelIDs(from: Data(#"{"data":"everything"}"#.utf8)) == nil)
        #expect(ModelCatalogResponse.modelIDs(from: Data("[]".utf8)) == nil)
    }

    @Test("An empty data array reads as an empty catalog")
    func emptyCatalog() {
        #expect(ModelCatalogResponse.modelIDs(from: Data(#"{"data":[]}"#.utf8)) == [])
    }

    @Test("Blank, non-string and repeated identifiers are dropped")
    func cleansIdentifiers() {
        let body = """
            {"data":[{"id":"b"},{"id":"b"},{"id":"   "},{"id":"a"},{"id":42},{"id":null},
            {"object":"model"},{"id":" c "}]}
            """
        #expect(ModelCatalogResponse.modelIDs(from: Data(body.utf8)) == ["a", "b", "c"])
    }

    @Test("Display names are read from name or display_name, keyed by identifier")
    func readsDisplayNames() {
        let body = """
            {"data":[{"id":"openai/gpt-4o","name":"OpenAI: GPT-4o"},
            {"id":"llama","display_name":" Llama 3 "},{"id":"same","name":"same"},
            {"id":"blank","name":"  "},{"id":"bare"},{"id":"odd","name":42}]}
            """
        #expect(
            ModelCatalogResponse.catalog(from: Data(body.utf8))?.displayNames
                == ["openai/gpt-4o": "OpenAI: GPT-4o", "llama": "Llama 3"])
    }

    @Test("Identifiers sort case-insensitively with a case-sensitive tie-break")
    func sortsPredictably() {
        let body = #"{"data":[{"id":"Zebra"},{"id":"apple"},{"id":"Apple"},{"id":"apple-2"}]}"#
        // Apple and apple are different identifiers, so both survive; the tie-break is
        // what stops their order depending on the sort implementation.
        #expect(
            ModelCatalogResponse.modelIDs(from: Data(body.utf8))
                == ["Apple", "apple", "apple-2", "Zebra"])
    }

    // MARK: - Building the request

    @Test("The request targets the provider's models endpoint")
    func targetsModelsEndpoint() throws {
        let request = try ModelCatalogRequest(
            baseURL: "https://api.groq.com/openai/v1", apiKey: "gsk_1"
        ).makeURLRequest()

        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/models")
        #expect(request.httpMethod == "GET")
    }

    @Test("A base URL with no version path still gets /models")
    func bareHostBaseURL() throws {
        // DeepSeek's published base URL is the bare host, which is where its catalog
        // lives — checked against the live endpoint.
        let request = try ModelCatalogRequest(
            baseURL: "https://api.deepseek.com", apiKey: "sk-1"
        ).makeURLRequest()

        #expect(request.url?.absoluteString == "https://api.deepseek.com/models")
    }

    @Test("A trailing slash on the base URL does not double up")
    func trailingSlashBaseURL() throws {
        let request = try ModelCatalogRequest(
            baseURL: "https://api.example.com/v1/", apiKey: "k"
        ).makeURLRequest()

        #expect(request.url?.absoluteString == "https://api.example.com/v1/models")
    }

    @Test("A key is sent as a bearer token, and omitted entirely when there is none")
    func authorizationHeader() throws {
        let withKey = try ModelCatalogRequest(
            baseURL: "https://api.example.com/v1", apiKey: "sk-1"
        ).makeURLRequest()
        #expect(withKey.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")

        // Local endpoints have no key; an empty Bearer would be a lie to the provider.
        let local = try ModelCatalogRequest(
            baseURL: "http://127.0.0.1:11434/v1", apiKey: ""
        ).makeURLRequest()
        #expect(local.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Plain HTTP is allowed for a local endpoint and refused for a remote one")
    func urlPolicy() {
        #expect(
            EndpointURLValidator.modelsURL(from: "http://127.0.0.1:11434/v1")?.absoluteString
                == "http://127.0.0.1:11434/v1/models")
        #expect(EndpointURLValidator.modelsURL(from: "http://api.example.com/v1") == nil)
        #expect(EndpointURLValidator.modelsURL(from: "not a url") == nil)
    }

    @Test("An unusable base URL is rejected before any network call")
    func rejectsUnusableBaseURL() {
        let request = ModelCatalogRequest(baseURL: "not a url", apiKey: "k")
        #expect(throws: AIError.self) {
            _ = try request.makeURLRequest()
        }
    }

    // MARK: - Redirect policy

    @Test("A redirect to the same host is followed, comparing hosts case-insensitively")
    func sameHostRedirectAllowed() {
        #expect(
            ModelCatalogLoader.allowsRedirect(
                from: URL(string: "https://API.Example.com/v1/models")!,
                to: URL(string: "https://api.example.com/v9/models")!))
    }

    @Test("A redirect to another host is refused")
    func crossHostRedirectRefused() {
        // The request carries an API key, so following a redirect elsewhere is a way to
        // have that key read by a third party.
        #expect(
            !ModelCatalogLoader.allowsRedirect(
                from: URL(string: "https://api.example.com/v1/models")!,
                to: URL(string: "https://evil.example.net/models")!))
    }

    @Test("A redirect to another port on the same host is refused")
    func crossPortRedirectRefused() {
        // The host alone does not identify the service being talked to.
        #expect(
            !ModelCatalogLoader.allowsRedirect(
                from: URL(string: "https://api.example.com/v1/models")!,
                to: URL(string: "https://api.example.com:8443/models")!))
    }

    @Test("HTTPS is never downgraded to plain HTTP, though a local endpoint may upgrade")
    func schemeDowngradeRefused() {
        #expect(
            !ModelCatalogLoader.allowsRedirect(
                from: URL(string: "https://api.example.com/v1/models")!,
                to: URL(string: "http://api.example.com/models")!))
        #expect(
            ModelCatalogLoader.allowsRedirect(
                from: URL(string: "http://127.0.0.1:11434/v1/models")!,
                to: URL(string: "https://127.0.0.1:11434/models")!))
    }

    // MARK: - Error bodies

    /// Bodies captured from the live endpoints while building this feature. Providers do
    /// not agree on an error shape, so the reader must not assume one.
    @Test(
        "Every real provider error body yields a readable message",
        arguments: [
            (#"{"error":{"message":"Invalid API Key"}}"#, "Invalid API Key"),
            (
                #"{"code":"unauthenticated:no-credentials","error":"No credentials presented."}"#,
                "No credentials presented."
            ),
            ("Missing API key", "Missing API key"),
        ])
    func readsProviderErrorBody(_ body: String, _ expected: String) {
        #expect(AIError.message(fromResponseBody: Data(body.utf8)) == expected)
    }

    @Test("A rejected key is reported with the provider's own words")
    func unauthorizedMessages() {
        #expect(
            ModelCatalogError.unauthorized("Invalid API Key").errorDescription
                == "The provider rejected this API key. Invalid API Key")
        // DeepSeek answers 401 with an empty body, which must not leave a trailing space.
        #expect(
            ModelCatalogError.unauthorized("").errorDescription
                == "The provider rejected this API key.")
    }

    // MARK: - Adding picked models

    @Test("Picked identifiers are appended as they are, with no alias")
    func addsPickedModels() {
        var form = EndpointFormState()
        form.addModels(names: ["gpt-4o", "llama-3.3-70b-versatile"])

        #expect(form.models.map(\.name) == ["gpt-4o", "llama-3.3-70b-versatile"])
        // Aliases collide case-insensitively and are what the user reads in the menu, so
        // none is invented from an identifier.
        #expect(form.models.allSatisfy { $0.alias == nil })
    }

    @Test("A picked model takes the provider's name as its alias")
    func picksUpProviderNames() {
        var form = EndpointFormState()
        form.addModels(
            names: ["openai/gpt-4o", "meta/llama"],
            aliases: ["openai/gpt-4o": "OpenAI: GPT-4o"])

        #expect(form.models.map(\.alias) == ["OpenAI: GPT-4o", nil])
    }

    @Test("A provider's name that collides is dropped, and the model still added")
    func collidingProviderNameIsDropped() {
        var form = EndpointFormState()
        form.models = [CustomModel(name: "m-1", alias: "GPT-4o")]

        form.addModels(names: ["openai/gpt-4o"], aliases: ["openai/gpt-4o": "gpt-4o"])

        #expect(form.models.map(\.name) == ["m-1", "openai/gpt-4o"])
        #expect(form.models.last?.alias == nil)
    }

    @Test("An identifier already on the endpoint is not added twice")
    func skipsDuplicates() {
        var form = EndpointFormState()
        form.models = [CustomModel(name: "gpt-4o")]

        form.addModels(names: ["gpt-4o", "gpt-4o-mini", "  gpt-4o  "])

        #expect(form.models.map(\.name) == ["gpt-4o", "gpt-4o-mini"])
    }

    @Test("Identifiers are compared case-sensitively, as providers treat them")
    func duplicateRuleIsCaseSensitive() {
        var form = EndpointFormState()
        form.models = [CustomModel(name: "gpt-4o")]

        form.addModels(names: ["GPT-4O"])

        #expect(form.models.map(\.name) == ["gpt-4o", "GPT-4O"])
    }

    @Test("Blank identifiers are skipped")
    func skipsBlankIdentifiers() {
        var form = EndpointFormState()
        form.addModels(names: ["  ", "fine", ""])
        #expect(form.models.map(\.name) == ["fine"])
    }

    @Test("Picked models make a form that was otherwise complete submittable")
    func pickedModelsSatisfyTheModelRule() {
        var form = EndpointFormState()
        form.name = "My Groq"
        form.baseURL = "https://api.groq.com/openai/v1"
        form.apiKey = "gsk_1"
        form.addModels(names: ["llama-3.3-70b-versatile"])

        #expect(form.canSubmit(in: .init(existingEndpoints: [])))
    }
}
