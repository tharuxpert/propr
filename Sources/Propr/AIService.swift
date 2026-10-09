import Foundation

/// Client for OpenAI-compatible chat completion APIs.
///
/// Request building lives in `ChatCompletionRequest` and response parsing in
/// `ChatCompletionResponse`, so this type is only responsible for the networking.
@MainActor
final class AIService {
    static let shared = AIService()

    /// How much of an error body to read before giving up, so a runaway response
    /// cannot be drained into memory.
    private static let maxErrorBodyBytes = 8_192

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: config)
    }

    /// Sends the original text + user instruction to the selected model and returns
    /// the refined text.
    func refine(
        original: String,
        instruction: String,
        history: [RefinementTurn] = [],
        selection: ModelSelection,
        apiKey: String,
        intent: RefineIntent = .auto
    ) async throws -> String {
        let request = try ChatCompletionRequest(
            original: original,
            instruction: instruction,
            history: history,
            selection: selection,
            apiKey: apiKey,
            stream: false,
            intent: intent
        ).makeURLRequest()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIError.apiError(
                statusCode: httpResponse.statusCode,
                message: AIError.message(fromResponseBody: data)
            )
        }

        guard let content = ChatCompletionResponse.content(from: data) else {
            throw AIError.invalidResponse
        }

        return content
    }

    /// Streaming version. Yields incremental text deltas as they arrive.
    func refineStream(
        original: String,
        instruction: String,
        history: [RefinementTurn] = [],
        selection: ModelSelection,
        apiKey: String,
        intent: RefineIntent = .auto
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let requestTask = Task {
                do {
                    let request = try ChatCompletionRequest(
                        original: original,
                        instruction: instruction,
                        history: history,
                        selection: selection,
                        apiKey: apiKey,
                        stream: true,
                        intent: intent
                    ).makeURLRequest()

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.networkError)
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let body = try await Self.readErrorBody(from: bytes)
                        continuation.finish(
                            throwing: AIError.apiError(
                                statusCode: httpResponse.statusCode,
                                message: AIError.message(fromResponseBody: body)
                            )
                        )
                        return
                    }

                    for try await line in bytes.lines {
                        switch ChatCompletionResponse.streamEvent(from: line) {
                        case .delta(let content):
                            continuation.yield(content)
                        case .done:
                            continuation.finish()
                            return
                        case .ignored:
                            continue
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                requestTask.cancel()
            }
        }
    }

    /// Reads an error response body so the user sees the provider's own message
    /// rather than a generic failure.
    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= maxErrorBodyBytes { break }
        }
        return body
    }
}
