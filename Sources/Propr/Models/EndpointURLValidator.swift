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
        guard let normalized = normalizedBaseURL(from: baseURL),
              let base = URL(string: normalized) else {
            return nil
        }

        return base
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
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
