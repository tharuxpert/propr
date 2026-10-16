import Foundation

/// The editable contents of an endpoint form, plus the rules that decide whether it
/// can be saved.
///
/// Adding an endpoint and editing one are the same form with the same rules, so they
/// share this type. They previously each carried their own copy of the validation,
/// which had already drifted: the edit path was missing the alias-collision checks
/// that the add path performed.
///
/// Deliberately free of SwiftUI and of any actor isolation, so the rules can be
/// tested directly without standing up a view.
struct EndpointFormState: Equatable {
    var name: String = ""
    var baseURL: String = ""
    var apiKey: String = ""
    var models: [CustomModel] = []

    /// The "add a model" row beneath the list, not yet committed to `models`.
    var draftModelName: String = ""
    var draftModelAlias: String = ""

    init() {}

    /// Seeds the form from an existing endpoint, for editing.
    init(endpoint: CustomEndpoint, apiKey: String = "") {
        self.name = endpoint.name
        self.baseURL = endpoint.baseURL
        self.apiKey = apiKey
        self.models = endpoint.models
    }
}

// MARK: - Validation

extension EndpointFormState {
    /// What the form is being validated against: the endpoints that already exist,
    /// and (when editing) the endpoint that should not count as its own duplicate.
    struct ValidationContext {
        let existingEndpoints: [CustomEndpoint]
        let excludingEndpointID: UUID?

        init(existingEndpoints: [CustomEndpoint], excludingEndpointID: UUID? = nil) {
            self.existingEndpoints = existingEndpoints
            self.excludingEndpointID = excludingEndpointID
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBaseURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAPIKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    func nameError(in context: ValidationContext) -> String? {
        let name = trimmedName
        if name.isEmpty {
            return "Endpoint name is required"
        }

        let clashes = context.existingEndpoints.contains { endpoint in
            endpoint.id != context.excludingEndpointID
                && endpoint.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if clashes {
            return "An endpoint with this name already exists"
        }

        return nil
    }

    var urlError: String? {
        let url = trimmedBaseURL
        if url.isEmpty {
            return "Endpoint URL is required"
        }
        if EndpointURLValidator.normalizedBaseURL(from: url) == nil {
            return "Use HTTPS for remote providers, or HTTP for localhost."
        }
        return nil
    }

    var apiKeyError: String? {
        guard urlError == nil,
            EndpointURLValidator.requiresAPIKey(for: baseURL),
            trimmedAPIKey.isEmpty
        else {
            return nil
        }
        return "API key is required for remote endpoints."
    }

    /// At least one model, none blank, no duplicate identifiers.
    var modelsAreValid: Bool {
        let names = models.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty }) else { return false }
        return Set(names).count == names.count
    }

    /// Whether the draft model row can be committed to `models`.
    ///
    /// Model identifiers are compared case-sensitively, because that is how providers
    /// treat them. Aliases are compared case-insensitively, because they are only ever
    /// shown to a human, and must not collide with another entry's display name or
    /// identifier.
    var canAddDraftModel: Bool {
        let name = draftModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        if models.contains(where: { $0.name == name }) {
            return false
        }

        let alias = draftModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return true }

        if models.contains(where: { $0.displayName.caseInsensitiveCompare(alias) == .orderedSame }) {
            return false
        }
        if models.contains(where: { $0.name.caseInsensitiveCompare(alias) == .orderedSame }) {
            return false
        }

        return true
    }

    func canSubmit(in context: ValidationContext) -> Bool {
        nameError(in: context) == nil
            && urlError == nil
            && apiKeyError == nil
            && modelsAreValid
    }
}

// MARK: - Mutation

extension EndpointFormState {
    /// Commits the draft model row. No-op when the draft is not valid, so callers do
    /// not have to re-check.
    mutating func addDraftModel() {
        guard canAddDraftModel else { return }

        let name = draftModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = draftModelAlias.trimmingCharacters(in: .whitespacesAndNewlines)

        models.append(CustomModel(name: name, alias: alias.isEmpty ? nil : alias))
        draftModelName = ""
        draftModelAlias = ""
    }

    mutating func removeModel(_ model: CustomModel) {
        models.removeAll { $0.id == model.id }
    }

    /// Appends models picked from the provider's own catalog.
    ///
    /// Enforces the identifier rule only: compared case-sensitively, and skipped when
    /// already present, exactly as `canAddDraftModel` does. No alias is set — an alias is
    /// what the user reads in the menu, and aliases collide case-insensitively against
    /// identifiers and other aliases, so one invented from an identifier would create a
    /// collision for the user to undo.
    ///
    /// Note this cannot reach the alias rules `canAddDraftModel` applies to a typed
    /// alias, because there is no alias to check. A display name matching an existing
    /// alias is possible here and equally possible by hand; the form has never ruled it
    /// out, and tightening it is a change to the manual path too, not to this one.
    mutating func addModels(names: [String]) {
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                !models.contains(where: { $0.name == trimmed })
            else { continue }

            models.append(CustomModel(name: trimmed))
        }
    }

    mutating func clearDraftModel() {
        draftModelName = ""
        draftModelAlias = ""
    }

    /// Builds the endpoint this form describes, normalising the URL.
    /// Returns nil when the form is not in a saveable state.
    func makeEndpoint(id: UUID = UUID(), in context: ValidationContext) -> CustomEndpoint? {
        guard canSubmit(in: context),
            let normalizedURL = EndpointURLValidator.normalizedBaseURL(from: trimmedBaseURL)
        else {
            return nil
        }

        return CustomEndpoint(
            id: id,
            name: trimmedName,
            baseURL: normalizedURL,
            models: models
        )
    }
}
