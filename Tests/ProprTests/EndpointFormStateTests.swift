import Foundation
import Testing

@testable import Propr

/// Pins the endpoint form rules that the Add and Edit flows both rely on.
///
/// These previously existed as two divergent copies inside ModelsSettingsView, so the
/// point of these tests is that a single rule change cannot silently apply to only one
/// of the two flows again.
struct EndpointFormStateTests {

    // MARK: - Helpers

    private func endpoint(
        _ name: String,
        id: UUID = UUID(),
        url: String = "https://api.example.com/v1",
        models: [CustomModel] = [CustomModel(name: "m1")]
    ) -> CustomEndpoint {
        CustomEndpoint(id: id, name: name, baseURL: url, models: models)
    }

    private func validForm() -> EndpointFormState {
        var form = EndpointFormState()
        form.name = "My Endpoint"
        form.baseURL = "https://api.example.com/v1"
        form.apiKey = "sk-test"
        form.models = [CustomModel(name: "gpt-4o")]
        return form
    }

    // MARK: - Name

    @Test("A blank name is rejected")
    func blankName() {
        var form = validForm()
        form.name = "   "
        #expect(form.nameError(in: .init(existingEndpoints: [])) == "Endpoint name is required")
    }

    @Test("Duplicate names are rejected regardless of case")
    func duplicateName() {
        var form = validForm()
        form.name = "my endpoint"
        let context = EndpointFormState.ValidationContext(
            existingEndpoints: [endpoint("My Endpoint")])
        #expect(form.nameError(in: context) == "An endpoint with this name already exists")
    }

    @Test("An endpoint being edited does not collide with itself")
    func editingKeepsOwnName() {
        let existingID = UUID()
        let existing = endpoint("My Endpoint", id: existingID)

        var form = EndpointFormState(endpoint: existing)
        form.apiKey = "sk-test"

        let editing = EndpointFormState.ValidationContext(
            existingEndpoints: [existing], excludingEndpointID: existingID)
        #expect(form.nameError(in: editing) == nil)

        // ...but the same name is still a duplicate when adding a new endpoint.
        let adding = EndpointFormState.ValidationContext(existingEndpoints: [existing])
        #expect(form.nameError(in: adding) != nil)
    }

    // MARK: - URL

    @Test("A blank URL is rejected")
    func blankURL() {
        var form = validForm()
        form.baseURL = ""
        #expect(form.urlError == "Endpoint URL is required")
    }

    @Test("Plain HTTP is rejected for remote hosts")
    func insecureRemoteURL() {
        var form = validForm()
        form.baseURL = "http://api.example.com/v1"
        #expect(form.urlError != nil)
    }

    @Test("Plain HTTP is allowed for localhost", arguments: [
        "http://localhost:11434/v1",
        "http://127.0.0.1:11434/v1",
    ])
    func localhostURL(_ url: String) {
        var form = validForm()
        form.baseURL = url
        form.apiKey = ""
        #expect(form.urlError == nil)
    }

    // MARK: - API key

    @Test("Remote endpoints require a key")
    func remoteRequiresKey() {
        var form = validForm()
        form.apiKey = "  "
        #expect(form.apiKeyError == "API key is required for remote endpoints.")
    }

    @Test("Local endpoints do not require a key")
    func localNeedsNoKey() {
        var form = validForm()
        form.baseURL = "http://127.0.0.1:11434/v1"
        form.apiKey = ""
        #expect(form.apiKeyError == nil)
    }

    @Test("No key error is reported while the URL itself is invalid")
    func keyErrorSuppressedForBadURL() {
        var form = validForm()
        form.baseURL = "not a url"
        form.apiKey = ""
        #expect(form.apiKeyError == nil)
    }

    // MARK: - Models

    @Test("At least one model is required")
    func modelsRequired() {
        var form = validForm()
        form.models = []
        #expect(form.modelsAreValid == false)
    }

    @Test("Blank and duplicate model identifiers are rejected")
    func badModelLists() {
        var blank = validForm()
        blank.models = [CustomModel(name: "  ")]
        #expect(blank.modelsAreValid == false)

        var duplicate = validForm()
        duplicate.models = [CustomModel(name: "gpt-4o"), CustomModel(name: "gpt-4o")]
        #expect(duplicate.modelsAreValid == false)
    }

    // MARK: - Draft model row

    @Test("A blank draft model cannot be added")
    func blankDraft() {
        var form = validForm()
        form.draftModelName = "   "
        #expect(form.canAddDraftModel == false)
    }

    @Test("Model identifiers are compared case-sensitively")
    func draftIdentifierIsCaseSensitive() {
        var form = validForm()
        form.models = [CustomModel(name: "gpt-4o")]

        form.draftModelName = "gpt-4o"
        #expect(form.canAddDraftModel == false)

        // Providers treat identifiers as case-sensitive, so this is a different model.
        form.draftModelName = "GPT-4O"
        #expect(form.canAddDraftModel == true)
    }

    /// This is the rule the edit flow was missing entirely before the two copies
    /// were merged — it validated only the identifier, never the alias.
    @Test("A draft alias cannot collide with an existing display name")
    func draftAliasCollidesWithDisplayName() {
        var form = validForm()
        form.models = [CustomModel(name: "m-1", alias: "Fast Model")]
        form.draftModelName = "m-2"
        form.draftModelAlias = "fast model"
        #expect(form.canAddDraftModel == false)
    }

    @Test("A draft alias cannot collide with an existing identifier")
    func draftAliasCollidesWithIdentifier() {
        var form = validForm()
        form.models = [CustomModel(name: "gpt-4o")]
        form.draftModelName = "m-2"
        form.draftModelAlias = "GPT-4o"
        #expect(form.canAddDraftModel == false)
    }

    @Test("Adding a draft model clears the draft row")
    func addingDraftClearsIt() {
        var form = validForm()
        form.models = []
        form.draftModelName = "gpt-4o"
        form.draftModelAlias = "GPT-4o mini"

        form.addDraftModel()

        #expect(form.models.count == 1)
        #expect(form.models.first?.name == "gpt-4o")
        #expect(form.models.first?.alias == "GPT-4o mini")
        #expect(form.draftModelName.isEmpty)
        #expect(form.draftModelAlias.isEmpty)
    }

    @Test("Adding an invalid draft model does nothing")
    func addingInvalidDraftIsNoOp() {
        var form = validForm()
        let before = form.models
        form.draftModelName = "   "
        form.addDraftModel()
        #expect(form.models == before)
    }

    @Test("An empty alias is stored as nil rather than an empty string")
    func emptyAliasBecomesNil() {
        var form = validForm()
        form.models = []
        form.draftModelName = "gpt-4o"
        form.draftModelAlias = "   "
        form.addDraftModel()
        #expect(form.models.first?.alias == nil)
    }

    @Test("Removing a model removes only that model")
    func removeModel() {
        var form = validForm()
        let keep = CustomModel(name: "keep")
        let drop = CustomModel(name: "drop")
        form.models = [keep, drop]

        form.removeModel(drop)

        #expect(form.models.map(\.name) == ["keep"])
    }

    // MARK: - Submission

    @Test("A complete form can be submitted")
    func validFormSubmits() {
        let form = validForm()
        #expect(form.canSubmit(in: .init(existingEndpoints: [])) == true)
    }

    @Test("Each individual rule blocks submission")
    func eachRuleBlocksSubmission() {
        let context = EndpointFormState.ValidationContext(existingEndpoints: [])

        var noName = validForm()
        noName.name = ""
        #expect(noName.canSubmit(in: context) == false)

        var badURL = validForm()
        badURL.baseURL = "http://api.example.com"
        #expect(badURL.canSubmit(in: context) == false)

        var noKey = validForm()
        noKey.apiKey = ""
        #expect(noKey.canSubmit(in: context) == false)

        var noModels = validForm()
        noModels.models = []
        #expect(noModels.canSubmit(in: context) == false)
    }

    @Test("Building an endpoint normalises the URL and trims the name")
    func makeEndpointNormalises() {
        var form = validForm()
        form.name = "  My Endpoint  "
        form.baseURL = "  HTTPS://API.Example.com/v1/  "

        let built = form.makeEndpoint(in: .init(existingEndpoints: []))

        #expect(built?.name == "My Endpoint")
        #expect(built?.baseURL == "https://api.example.com/v1")
    }

    @Test("An invalid form builds no endpoint")
    func makeEndpointRejectsInvalid() {
        var form = validForm()
        form.models = []
        #expect(form.makeEndpoint(in: .init(existingEndpoints: [])) == nil)
    }

    @Test("Seeding from an existing endpoint reproduces its contents")
    func seedFromEndpoint() {
        let models = [CustomModel(name: "a"), CustomModel(name: "b", alias: "B")]
        let existing = endpoint("Mine", url: "https://x.example.com/v1", models: models)

        let form = EndpointFormState(endpoint: existing, apiKey: "sk-1")

        #expect(form.name == "Mine")
        #expect(form.baseURL == "https://x.example.com/v1")
        #expect(form.apiKey == "sk-1")
        #expect(form.models == models)
    }
}
