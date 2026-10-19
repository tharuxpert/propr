import Foundation

enum EndpointURLValidator {
    static func normalizedBaseURL(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        guard scheme == "https" || isLocalHost(host) else {
            return nil
        }

        components.scheme = scheme
        components.host = host

        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.url?.absoluteString
    }

    static func chatCompletionsURL(from baseURL: String) -> URL? {
        guard let base = normalizedURL(from: baseURL) else { return nil }

        return base
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    /// The route that lists a provider's models, which is where the Add Provider sheet
    /// gets the identifiers a user would otherwise have to look up themselves.
    static func modelsURL(from baseURL: String) -> URL? {
        normalizedURL(from: baseURL)?.appendingPathComponent("models")
    }

    private static func normalizedURL(from baseURL: String) -> URL? {
        guard let normalized = normalizedBaseURL(from: baseURL) else { return nil }
        return URL(string: normalized)
    }

    static func requiresAPIKey(for baseURL: String) -> Bool {
        guard let normalized = normalizedBaseURL(from: baseURL),
              let host = URL(string: normalized)?.host?.lowercased() else {
            return true
        }

        return !isLocalHost(host)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1"
    }
}
