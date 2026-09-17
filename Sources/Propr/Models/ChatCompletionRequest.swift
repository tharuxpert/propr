import Foundation

/// Builds the OpenAI-compatible chat-completion request Propr sends to a provider.
///
/// The streaming and non-streaming calls previously each assembled their own copy of
/// the URL, headers, prompts and payload — identical apart from the `stream` flag.
/// They share this instead, so a change to the prompt or payload cannot apply to only
/// one of the two paths.
///
/// Free of URLSession and of actor isolation so the request it produces can be
/// inspected directly in tests.
struct ChatCompletionRequest {
    let original: String
    let instruction: String
    let selection: ModelSelection
    let apiKey: String
    let stream: Bool

    /// Whether there is existing text to work on, as opposed to a request to write
    /// something from scratch.
    var hasOriginalText: Bool {
        !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Used when the user has selected text, or the field's contents were readable.
    static let refineSystemPrompt = """
        You are a helpful writing assistant. Follow the user's instruction precisely.
        Only return the rewritten text. Do not add explanations, quotes, or markdown unless the user asked for it.
        """

    /// Used when there is nothing to rewrite — the user summoned the bar at an empty
    /// cursor and is asking for text to be produced, such as a shell command.
    /// Telling a "writing assistant" to rewrite nothing produces worse answers than
    /// simply asking for what they want.
    static let generateSystemPrompt = """
        You write text that will be typed directly into whatever the user is working in.
        Answer with exactly the text they asked for and nothing else. Do not add explanations, \
        preamble, quotes, or markdown fences unless the user asked for them.
        """

    var systemPrompt: String {
        hasOriginalText ? Self.refineSystemPrompt : Self.generateSystemPrompt
    }

    var userPrompt: String {
        guard hasOriginalText else { return instruction }

        return """
            Original text:
            \(original)

            Instruction:
            \(instruction)
            """
    }

    var payload: [String: Any] {
        var payload: [String: Any] = [
            "model": selection.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.7,
            "max_tokens": 2048,
        ]
        if stream {
            payload["stream"] = true
        }
        return payload
    }

    /// - Throws: `AIError.invalidEndpoint` when the selection's base URL is not usable.
    func makeURLRequest() throws -> URLRequest {
        guard let url = EndpointURLValidator.chatCompletionsURL(from: selection.baseURL) else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

/// Parsing of the provider's responses. Separated from the networking so the shapes
/// can be tested without a server.
enum ChatCompletionResponse {
    /// Extracts the message content from a non-streaming response body.
    static func content(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line of a server-sent-events stream.
    enum StreamEvent: Equatable {
        /// A chunk of generated text.
        case delta(String)
        /// The provider signalled the end of the stream.
        case done
        /// Keep-alives, comments and chunks carrying no content.
        case ignored
    }

    static func streamEvent(from line: String) -> StreamEvent {
        guard line.hasPrefix("data: ") else { return .ignored }

        let payload = String(line.dropFirst(6))
        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return .done
        }

        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let delta = first["delta"] as? [String: Any],
            let content = delta["content"] as? String
        else {
            return .ignored
        }

        return .delta(content)
    }
}
