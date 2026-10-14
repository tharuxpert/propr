import Foundation

/// Web destinations available in the floating lookup panel.
enum SearchProvider: String, CaseIterable, Sendable {
    case google
    case ai

    var title: String {
        switch self {
        case .google: "Google"
        case .ai: "AI"
        }
    }

    var injectedJS: String? {
        guard self == .google else { return nil }
        return """
            // Auto-dismiss Google GDPR cookie consent (consent.google.com redirect)
            (function() {
              function dismissConsent() {
                if (!location.hostname.includes('consent.google')) return false;
                var btn = document.querySelector('form[action*="/save"] button');
                if (btn) { btn.click(); return true; }
                return false;
              }
              if (!dismissConsent()) setTimeout(dismissConsent, 1000);
            })();
            """
    }

    func searchURL(for query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"

        switch self {
        case .google:
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "igu", value: "1")
            ]
        case .ai:
            return nil
        }

        return components.url
    }
}

extension SearchProvider {
    static let defaultForLookupKey = "lookup.defaultProvider"

    /// The source a new lookup opens on, chosen in Settings. Google when unset or
    /// when the stored value no longer names a provider.
    static var defaultForLookup: SearchProvider {
        defaultForLookup(stored: UserDefaults.standard.string(forKey: defaultForLookupKey))
    }

    static func defaultForLookup(stored: String?) -> SearchProvider {
        stored.flatMap(SearchProvider.init(rawValue:)) ?? .google
    }
}
