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

    /// Whether `name` can be added as a new model: not blank, and not an identifier
    /// already on the list. Identifiers are compared case-sensitively, because that
    /// is how providers treat them.
    func canAddModel(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !models.contains(where: { $0.name == name })
    }

    /// Why `alias` cannot be the name Propr shows for `model`, or nil when it can.
    ///
    /// Aliases are compared case-insensitively, because they are only ever shown to a
    /// human, and must not collide with another model's display name or identifier.
    /// A blank alias is always fine: it clears the alias.
    func aliasError(_ alias: String, for model: CustomModel) -> String? {
        let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return nil }

        let clashes = models.contains { other in
            other.id != model.id
                && (other.displayName.caseInsensitiveCompare(alias) == .orderedSame
                    || other.name.caseInsensitiveCompare(alias) == .orderedSame)
        }
        return clashes ? "Another model already goes by this name." : nil
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
    /// Gives `model` a new alias, or clears it when `alias` is blank or just repeats
    /// the identifier. No-op when `aliasError` rejects it, so callers do not have to
    /// re-check.
    mutating func setAlias(_ alias: String, for model: CustomModel) {
        guard aliasError(alias, for: model) == nil,
            let index = models.firstIndex(where: { $0.id == model.id })
        else { return }

        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        models[index].alias = trimmed.isEmpty || trimmed == models[index].name ? nil : trimmed
    }

    mutating func removeModel(_ model: CustomModel) {
        models.removeAll { $0.id == model.id }
    }

    /// Appends models, picked from the provider's catalog or typed by hand.
    ///
    /// Enforces the identifier rule of `canAddModel(named:)` and skips what it rejects.
    /// No alias is set — an alias is what the user reads in the menu, and aliases
    /// collide case-insensitively against identifiers and other aliases, so one
    /// invented from an identifier would create a collision for the user to undo.
    /// One is given afterwards with `setAlias(_:for:)`, which checks those rules.
    mutating func addModels(names: [String]) {
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard canAddModel(named: trimmed) else { continue }
            models.append(CustomModel(name: trimmed))
        }
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
