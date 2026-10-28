import Foundation
import Testing

@testable import Propr

/// Pins the HTTP handling of a catalog fetch: how a status becomes something the sheet
/// can show, and that a provider publishing no catalog is never mistaken for one whose
/// catalog is empty.
///
/// The stub picks its reply from the request's host, so no mutable state is shared
/// between tests and this suite stays safe to run in parallel with the others.
struct ModelCatalogFetchTests {

    // MARK: - Helpers

    /// A base URL whose host names the reply the stub should serve.
    private func baseURL(_ scenario: String) -> String {
        "https://\(scenario).catalog.test/v1"
    }

    private func fetchIDs(_ scenario: String) async -> Result<[String], ModelCatalogError> {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogStub.self]

        return await ModelCatalogLoader.fetchCatalog(
            baseURL: baseURL(scenario),
            apiKey: "sk-test",
            session: URLSession(configuration: configuration)
        ).map(\.ids)
    }

    // MARK: - Success

    @Test("A successful fetch returns the provider's identifiers")
    func success() async {
        #expect(await fetchIDs("ok") == .success(["gpt-4o", "gpt-4o-mini"]))
    }

    @Test("An empty catalog is reported as empty, not as a missing catalog")
    func emptyCatalog() async {
        #expect(await fetchIDs("emptycatalog") == .failure(.empty))
    }

    @Test("A reply that is not a catalog is reported as unsupported")
    func unrecognisedCatalog() async {
        #expect(await fetchIDs("nocatalog") == .failure(.unsupported))
    }

    // MARK: - Rejected key

    /// Every one of these bodies came off a live preset endpoint. They do not agree on a
    /// shape, which is why the reader must not assume one.
    @Test(
        "A rejected key keeps the provider's own words, whatever shape they arrive in",
        arguments: [
            ("unauthorized", "Invalid API Key"),
            ("stringerror", "No credentials presented."),
            ("plaintext", "Missing API key"),
        ])
    func rejectedKey(_ scenario: String, _ message: String) async {
        #expect(await fetchIDs(scenario) == .failure(.unauthorized(message)))
    }

    @Test("A 401 with no body at all is still a rejected key, with nothing appended")
    func rejectedKeyWithNoBody() async {
        // DeepSeek answers 401 with a body and no Content-Type; this is the empty case.
        #expect(await fetchIDs("emptybody") == .failure(.unauthorized("")))
    }

    // MARK: - No catalog route

    @Test("A missing route is reported as unsupported rather than as a failure", arguments: [
        "notfound",
        "methodnotallowed",
    ])
    func missingRoute(_ scenario: String) async {
        #expect(await fetchIDs(scenario) == .failure(.unsupported))
    }

    @Test("Any other status carries the provider's message")
    func serverError() async {
        #expect(
            await fetchIDs("servererror")
                == .failure(.failed(statusCode: 500, message: "upstream exploded")))
    }

    // MARK: - Oversized replies

    @Test("A body over the cap is refused rather than parsed")
    func oversizedBody() async {
        // The stub sends no Content-Length, exactly as OpenRouter does, so only the
        // counting pass can stop this. Without it the read would be unbounded.
        #expect(await fetchIDs("oversized") == .failure(.tooLarge))
    }
}

/// Serves a canned reply chosen by the first label of the request's host.
private final class CatalogStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let scenario = url.host()?.split(separator: ".").first.map(String.init) ?? "unknown"
        let reply = Self.reply(for: scenario)

        var headers: [String: String] = [:]
        if let contentType = reply.contentType {
            headers["Content-Type"] = contentType
        }

        guard
            let response = HTTPURLResponse(
                url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func reply(for scenario: String) -> (status: Int, body: Data, contentType: String?) {
        switch scenario {
        case "ok":
            return (200, json(#"{"object":"list","data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}"#), "application/json")
        case "emptycatalog":
            return (200, json(#"{"data":[]}"#), "application/json")
        case "nocatalog":
            return (200, json(#"{"models":[{"name":"llama3.2:latest"}]}"#), "application/json")
        case "unauthorized":
            return (401, json(#"{"error":{"message":"Invalid API Key"}}"#), "application/json")
        case "stringerror":
            return (
                401,
                json(#"{"code":"unauthenticated:no-credentials","error":"No credentials presented."}"#),
                "application/json"
            )
        case "plaintext":
            return (401, Data("Missing API key".utf8), "text/plain")
        case "emptybody":
            return (401, Data(), nil)
        case "notfound":
            return (404, json(#"{"error":{"message":"not found"}}"#), "application/json")
        case "methodnotallowed":
            return (405, Data(), nil)
        case "servererror":
            return (500, json(#"{"error":{"message":"upstream exploded"}}"#), "application/json")
        case "oversized":
            return (
                200, Data(repeating: UInt8(ascii: "x"), count: ModelCatalogLoader.maxCatalogBytes + 1_024),
                "application/json"
            )
        default:
            return (500, Data(), nil)
        }
    }

    private static func json(_ text: String) -> Data { Data(text.utf8) }
}
