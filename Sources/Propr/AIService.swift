import Foundation

/// Basic non-streaming client for OpenAI-compatible chat completion APIs.
/// Designed to be called from the floating bar when the user submits a prompt.
@MainActor
final class AIService {
    static let shared = AIService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: config)
    }

    /// Sends the original text + user instruction to the selected model and returns the refined text.
    func refine(
        original: String,
        instruction: String,
        selection: ModelSelection,
        apiKey: String
    ) async throws -> String {
        guard let url = EndpointURLValidator.chatCompletionsURL(from: selection.baseURL) else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let systemPrompt = """
        You are a helpful writing assistant. Follow the user's instruction precisely.
        Only return the rewritten text. Do not add explanations, quotes, or markdown unless the user asked for it.
        """

        let userPrompt = """
        Original text:
        \(original)

        Instruction:
        \(instruction)
        """

        let payload: [String: Any] = [
            "model": selection.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIError.apiError(
                statusCode: httpResponse.statusCode,
                message: Self.humanReadableErrorMessage(from: data)
            )
        }

        // Parse OpenAI-compatible response
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streaming version. Yields incremental text deltas as they arrive from the model.
    func refineStream(
        original: String,
        instruction: String,
        selection: ModelSelection,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = EndpointURLValidator.chatCompletionsURL(from: selection.baseURL) else {
                        continuation.finish(throwing: AIError.invalidEndpoint)
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    let systemPrompt = """
                    You are a helpful writing assistant. Follow the user's instruction precisely.
                    Only return the rewritten text. Do not add explanations, quotes, or markdown unless the user asked for it.
                    """

                    let userPrompt = """
                    Original text:
                    \(original)

                    Instruction:
                    \(instruction)
                    """

                    let payload: [String: Any] = [
                        "model": selection.modelName,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "temperature": 0.7,
                        "max_tokens": 2048,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.networkError)
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        // Read the error body so the user sees the provider's actual
                        // message rather than a generic failure. Capped so a runaway
                        // response cannot be drained into memory.
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 8_192 { break }
                        }
                        continuation.finish(
                            throwing: AIError.apiError(
                                statusCode: httpResponse.statusCode,
                                message: Self.humanReadableErrorMessage(from: body)
                            )
                        )
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let dataString = String(line.dropFirst(6))

                            if dataString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let data = dataString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Pulls the readable message out of an error body instead of showing raw JSON.
    ///
    /// OpenAI-compatible providers return `{"error": {"message": "..."}}`, but some
    /// use `{"error": "..."}` or `{"message": "..."}`. Anything unrecognised falls
    /// back to the raw body so information is never lost.
    private static func humanReadableErrorMessage(from data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "Unknown error"

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any]
        else {
            return trimmedErrorMessage(raw)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return trimmedErrorMessage(message)
        }

        if let error = object["error"] as? String, !error.isEmpty {
            return trimmedErrorMessage(error)
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return trimmedErrorMessage(message)
        }

        return trimmedErrorMessage(raw)
    }

    private static func trimmedErrorMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 500 else { return trimmed }
        return String(trimmed.prefix(500)) + "..."
    }
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case networkError
    case apiError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key found for the selected model."
        case .invalidEndpoint:
            return "The selected endpoint URL is invalid. Use HTTPS for remote providers or HTTP for localhost."
        case .networkError:
            return "Network request failed."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Received an invalid response from the model provider."
        }
    }
}
