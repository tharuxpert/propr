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

    // MARK: - Adding and naming models

    @Test("A blank model cannot be added")
    func blankModel() {
        #expect(validForm().canAddModel(named: "   ") == false)
    }

    @Test("Model identifiers are compared case-sensitively")
    func identifierIsCaseSensitive() {
        var form = validForm()
        form.models = [CustomModel(name: "gpt-4o")]

        #expect(form.canAddModel(named: "gpt-4o") == false)
        #expect(form.canAddModel(named: " gpt-4o ") == false)
        // Providers treat identifiers as case-sensitive, so this is a different model.
        #expect(form.canAddModel(named: "GPT-4O") == true)
    }

    @Test("An alias cannot collide with another model's display name")
    func aliasCollidesWithDisplayName() {
        var form = validForm()
        let other = CustomModel(name: "m-2")
        form.models = [CustomModel(name: "m-1", alias: "Fast Model"), other]
        #expect(form.aliasError("fast model", for: other) != nil)
    }

    @Test("An alias cannot collide with another model's identifier")
    func aliasCollidesWithIdentifier() {
        var form = validForm()
        let other = CustomModel(name: "m-2")
        form.models = [CustomModel(name: "gpt-4o"), other]
        #expect(form.aliasError("GPT-4o", for: other) != nil)
    }

    @Test("A model may keep its own alias, in any case")
    func aliasDoesNotCollideWithItself() {
        var form = validForm()
        let model = CustomModel(name: "m-1", alias: "Fast Model")
        form.models = [model]
        #expect(form.aliasError("FAST MODEL", for: model) == nil)
    }

    @Test("Setting an alias trims it and changes only that model")
    func setAlias() {
        var form = validForm()
        let model = CustomModel(name: "gpt-4o")
        form.models = [model, CustomModel(name: "m-2")]

        form.setAlias("  GPT-4o mini \n", for: model)

        #expect(form.models.map(\.alias) == ["GPT-4o mini", nil])
    }

    @Test("A blank alias, or one that repeats the identifier, clears the alias")
    func clearingAlias() {
        var form = validForm()
        let model = CustomModel(name: "gpt-4o", alias: "Old")
        form.models = [model]

        form.setAlias("   ", for: model)
        #expect(form.models.first?.alias == nil)

        form.models = [model]
        form.setAlias("gpt-4o", for: model)
        #expect(form.models.first?.alias == nil)
    }

    @Test("A rejected alias changes nothing")
    func rejectedAliasIsNoOp() {
        var form = validForm()
        let model = CustomModel(name: "m-2", alias: "Kept")
        form.models = [CustomModel(name: "gpt-4o"), model]
        let before = form.models

        form.setAlias("GPT-4o", for: model)

        #expect(form.models == before)
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
