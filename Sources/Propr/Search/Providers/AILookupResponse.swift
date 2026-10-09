import Foundation

/// Interprets successful HTTP responses from OpenAI-compatible lookup endpoints.
/// A 2xx status alone does not mean the provider returned usable answer text.
enum AILookupResponse {
    static func answer(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.responseIssue("The provider returned a response that wasn't valid JSON.")
        }

        if json["error"] != nil {
            throw AIError.responseIssue("Provider error: \(AIError.message(fromResponseBody: data))")
        }
        if json["choices"] == nil, let message = nonempty(json["message"] as? String) {
            throw AIError.responseIssue(AIError.trimmed(message))
        }

        guard let choices = json["choices"] as? [[String: Any]] else {
            throw AIError.responseIssue(
                "The provider didn't return chat choices. Check that this model supports the chat completions endpoint.")
        }
        guard let choice = choices.first else {
            throw AIError.responseIssue("The provider returned no chat choices.")
        }
        guard let message = choice["message"] as? [String: Any] else {
            throw AIError.responseIssue("The provider returned a chat choice without a message.")
        }

        if let text = nonempty(message["content"] as? String) {
            return text
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if let text = nonempty(text) { return text }
        }
        if let refusal = nonempty(message["refusal"] as? String) {
            return refusal
        }

        switch choice["finish_reason"] as? String {
        case "length":
            throw AIError.responseIssue(
                "The model hit the output-token limit before returning an answer.")
        case "content_filter":
            throw AIError.responseIssue("The provider filtered the model's answer.")
        case "tool_calls", "function_call":
            throw AIError.responseIssue(
                "The model returned a tool call instead of an answer. Lookup does not support tools.")
        case "stop":
            throw AIError.responseIssue("The model returned an empty answer.")
        case .some(let reason):
            throw AIError.responseIssue(
                "The provider returned no answer text (finish reason: \(AIError.trimmed(reason))).")
        case .none:
            throw AIError.responseIssue("The provider returned no answer text.")
        }
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
