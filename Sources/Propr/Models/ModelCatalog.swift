import Foundation
import Observation

/// Builds the request that lists a provider's models.
///
/// Free of URLSession and of actor isolation so the URL and the headers can be tested
/// without a server, the way `ChatCompletionRequest` is.
///
/// Propr deliberately ships no baked-in model list — identifiers churn and a list in
/// the binary is stale the moment it ships (`BuiltInProvider`). Asking the provider
/// instead is the same idea one step further on: the user gets real identifiers, and
/// nothing in the app has to be kept current.
struct ModelCatalogRequest {
    let baseURL: String
    let apiKey: String

    /// - Throws: `AIError.invalidEndpoint` when the base URL is not usable.
    func makeURLRequest() throws -> URLRequest {
        guard let url = EndpointURLValidator.modelsURL(from: baseURL) else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Local endpoints have no key at all; sending an empty bearer would be a lie.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// Reading of the catalog reply, separated from the networking so the shapes can be
/// tested without a server.
enum ModelCatalogResponse {
    /// The model identifiers in `{"data": [{"id": "..."}]}`, deduplicated and sorted
    /// for a list a human has to scan.
    ///
    /// Returns nil — not an empty list — when the reply is not that shape, so a provider
    /// that publishes no catalog is told apart from one whose catalog is genuinely
    /// empty. Providers agree on this one shape: it is what OpenAI, Groq, xAI, Together,
    /// Fireworks, OpenRouter, DeepSeek, MiMo and Ollama all serve from `/v1/models`.
    ///
    /// Only `id` is read. Ollama's native `{"models": [{"name": ...}]}` is deliberately
    /// not accepted: those identifiers are not `chat/completions` model names, so
    /// accepting them would produce entries that fail on first use.
    static func modelIDs(from data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["data"] as? [[String: Any]]
        else {
            return nil
        }

        var seen = Set<String>()
        let ids = entries.compactMap { entry -> String? in
            guard let id = entry["id"] as? String else { return nil }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }

        // Case-insensitive so the list reads alphabetically, with a case-sensitive
        // tie-break so two identifiers differing only in case still sort predictably.
        return ids.sorted { first, second in
            let left = first.lowercased()
            let right = second.lowercased()
            return left == right ? first < second : left < right
        }
    }
}

/// Why a catalog could not be loaded, in the terms the sheet has to explain it.
enum ModelCatalogError: Error, Equatable, LocalizedError {
    /// The provider rejected the key. Carries the provider's own words, when it gave any.
    case unauthorized(String)
    /// The endpoint answered, but does not publish a model list.
    case unsupported
    /// The endpoint answered with a list containing no models.
    case empty
    /// The provider reported an error of its own.
    case failed(statusCode: Int, message: String)
    case network
    case invalidEndpoint
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unauthorized(let message):
            let detail = message.isEmpty ? "" : " \(message)"
            return "The provider rejected this API key.\(detail)"
        case .unsupported:
            return "This endpoint doesn't publish a model list. Add model IDs by hand."
        case .empty:
            return "The provider returned no models."
        case .failed(let statusCode, let message):
            return "The provider replied \(statusCode): \(message)"
        case .network:
            return "Could not reach the endpoint."
        case .invalidEndpoint:
            return "The endpoint URL is not usable."
        case .tooLarge:
            return "The provider's model list was too large to read."
        }
    }
}

/// Loads one sheet's model catalog and holds the state of the attempt.
///
/// Deliberately an instance rather than a singleton, unlike `ProviderIconStore`. The
/// result belongs to the URL being typed in this sheet, so a cache shared between
/// sheets would outlive the thing it describes. It dies with the sheet, and every
/// sheet therefore asks afresh — which is also why there is no disk
/// cache and no expiry to reason about.
@MainActor
@Observable
final class ModelCatalogLoader {
    /// Every identifier the provider returned, deduplicated and sorted. Empty until a
    /// load succeeds.
    private(set) var ids: [String] = []
    private(set) var isFetching = false
    private(set) var error: ModelCatalogError?

    private var task: Task<Void, Never>?

    /// The catalog a response may carry before Propr stops reading it.
    ///
    /// Not a tight limit: a truncated body would fail to parse and be reported as
    /// "no model list", which would be a lie about a provider that has one. OpenRouter
    /// answers with 465 entries and 778 KB today, so this is roughly five times the
    /// largest catalog seen. It exists to bound a broken or hostile response, not to
    /// police real ones.
    ///
    /// `nonisolated` because only the off-main-actor fetch reads it.
    nonisolated static let maxCatalogBytes = 4 * 1_024 * 1_024

    /// Fetches the catalog, replacing whatever the previous attempt produced.
    func load(baseURL: String, apiKey: String) {
        task?.cancel()
        isFetching = true
        error = nil

        task = Task { [weak self] in
            let result = await Self.fetchIDs(baseURL: baseURL, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    /// Drops the catalog, its error and any attempt in flight.
    ///
    /// An edit to the base URL has to do this: identifiers fetched from one host must
    /// never be addable to another, or a typo corrected after a load would append the
    /// wrong provider's models.
    func reset() {
        task?.cancel()
        task = nil
        ids = []
        error = nil
        isFetching = false
    }

    /// Stops a load in flight without touching what is on screen. Used when the sheet
    /// goes away, so a request carrying an API key does not outlive it.
    func cancel() {
        task?.cancel()
        task = nil
        isFetching = false
    }

    private func apply(_ result: Result<[String], ModelCatalogError>) {
        isFetching = false
        switch result {
        case .success(let ids):
            self.ids = ids
            error = nil
        case .failure(let error):
            ids = []
            self.error = error
        }
    }
}

// MARK: - Network

extension ModelCatalogLoader {
    /// Fetches and parses the catalog, off the main actor.
    ///
    /// Takes the two strings rather than a `URLRequest` so nothing but `Sendable` value
    /// types crosses the boundary, and so the request is built on the thread that uses it.
    /// - Parameter session: Injected by tests, so the status handling can be exercised
    ///   without a server. Left nil by the app, which builds an ephemeral session that
    ///   carries the redirect guard.
    nonisolated static func fetchIDs(
        baseURL: String, apiKey: String, session: URLSession? = nil
    ) async -> Result<[String], ModelCatalogError> {
        let request: URLRequest
        do {
            request = try ModelCatalogRequest(baseURL: baseURL, apiKey: apiKey).makeURLRequest()
        } catch {
            return .failure(.invalidEndpoint)
        }

        guard let url = request.url else { return .failure(.invalidEndpoint) }

        let activeSession =
            session
            ?? URLSession(
                configuration: .ephemeral,
                delegate: SameHostRedirectGuard(origin: url),
                delegateQueue: nil
            )
        // An injected session is the caller's to tear down.
        defer { if session == nil { activeSession.finishTasksAndInvalidate() } }

        do {
            let (data, response) = try await readBody(request, from: activeSession)

            guard let http = response as? HTTPURLResponse else {
                return .failure(.network)
            }

            guard (200...299).contains(http.statusCode) else {
                // Error bodies are not uniform: JSON `{"error": {...}}` from OpenAI, a
                // bare `{"error": "..."}` string from xAI, plain text from Together, and
                // plain text with no Content-Type at all from DeepSeek. `AIError` already
                // reads all four, so the body is never gated on being JSON.
                let message = AIError.message(fromResponseBody: data)
                switch http.statusCode {
                case 401, 403:
                    return .failure(.unauthorized(message))
                case 404, 405:
                    return .failure(.unsupported)
                default:
                    return .failure(.failed(statusCode: http.statusCode, message: message))
                }
            }

            guard let ids = ModelCatalogResponse.modelIDs(from: data) else {
                return .failure(.unsupported)
            }
            return ids.isEmpty ? .failure(.empty) : .success(ids)
        } catch is CatalogTooLarge {
            return .failure(.tooLarge)
        } catch {
            return .failure(.network)
        }
    }

    /// Reads the whole body, refusing anything over `maxCatalogBytes`.
    ///
    /// The declared length is checked first, then the stream is counted as it arrives, so
    /// a server that understates its size still cannot exhaust memory. The counting pass
    /// is not optional book-keeping: OpenRouter answers with `Content-Length: -1`, so for
    /// the largest catalog Propr knows of there is no declared length to trust at all.
    /// Measured warm, it costs about 30 ms over a buffered read of that 778 KB response,
    /// against a request the user has deliberately pressed a button for.
    private nonisolated static func readBody(
        _ request: URLRequest, from session: URLSession
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard response.expectedContentLength <= Int64(maxCatalogBytes) else {
            throw CatalogTooLarge()
        }

        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= maxCatalogBytes else { throw CatalogTooLarge() }
        }
        return (data, response)
    }
}

/// A body larger than the cap. Private because it only ever leaves `readBody` to be
/// reported as `ModelCatalogError.tooLarge`.
private struct CatalogTooLarge: Error {}

/// Refuses any redirect that would carry the request — and the API key in its headers —
/// somewhere other than the host the user actually typed.
///
/// `ProviderIconStore`'s equivalent exists so an untrusted page cannot aim Propr's
/// requests at the local network. This one exists because the catalog request carries a
/// bearer token, which makes a redirect a way to have the key read by a third party.
private final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url,
            ModelCatalogLoader.allowsRedirect(from: origin, to: url)
        else {
            return nil
        }
        return request
    }
}

extension ModelCatalogLoader {
    /// Whether a redirect may be followed: the same host and port, and never down from
    /// HTTPS to plain HTTP, which would put the key on the wire in the clear.
    ///
    /// The port is part of it because the host alone does not identify the service being
    /// talked to — a redirect is free to name a different one.
    nonisolated static func allowsRedirect(from origin: URL, to destination: URL) -> Bool {
        guard let originHost = origin.host()?.lowercased(),
            destination.host()?.lowercased() == originHost,
            destination.port == origin.port,
            let originScheme = origin.scheme?.lowercased(),
            let destinationScheme = destination.scheme?.lowercased()
        else {
            return false
        }

        // Same scheme, or an upgrade from plain HTTP to HTTPS. Never a downgrade.
        return destinationScheme == "https" || destinationScheme == originScheme
    }
}
