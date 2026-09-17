import Foundation

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

extension AIError {
    /// The longest provider message shown to the user before it is truncated.
    private static let maxMessageLength = 500

    /// Pulls the readable message out of an error body instead of surfacing raw JSON.
    ///
    /// OpenAI-compatible providers return `{"error": {"message": "..."}}`, but some
    /// use `{"error": "..."}` or `{"message": "..."}`. Anything unrecognised falls
    /// back to the raw body, so information is never lost — a message the user cannot
    /// read is still better than one they never see.
    static func message(fromResponseBody data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "Unknown error"

        guard let json = try? JSONSerialization.jsonObject(with: data),
            let object = json as? [String: Any]
        else {
            return trimmed(raw)
        }

        if let error = object["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        {
            return trimmed(message)
        }

        if let error = object["error"] as? String, !error.isEmpty {
            return trimmed(error)
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return trimmed(message)
        }

        return trimmed(raw)
    }

    static func trimmed(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxMessageLength else { return trimmed }
        return String(trimmed.prefix(maxMessageLength)) + "..."
    }
}
