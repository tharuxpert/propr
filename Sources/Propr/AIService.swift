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
        guard !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        let url = URL(string: selection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
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
                    guard !apiKey.isEmpty else {
                        continuation.finish(throwing: AIError.missingAPIKey)
                        return
                    }

                    let url = URL(string: selection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
                        // For streaming errors, try to read the body if possible (limited)
                        continuation.finish(throwing: AIError.apiError(statusCode: httpResponse.statusCode, message: "Streaming request failed"))
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
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case missingAPIKey
    case networkError
    case apiError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key found for the selected model."
        case .networkError:
            return "Network request failed."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Received an invalid response from the model provider."
        }
    }
}
