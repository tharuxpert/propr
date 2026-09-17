import Foundation
import Testing

@testable import Propr

/// Covers request building, response parsing and provider error messages — the parts
/// of the AI path that are pure and therefore checkable without a server.
struct ChatCompletionTests {

    private func selection(
        baseURL: String = "https://api.example.com/v1",
        model: String = "gpt-4o"
    ) -> ModelSelection {
        ModelSelection(
            id: UUID(),
            displayName: model,
            endpointID: UUID(),
            modelName: model,
            baseURL: baseURL
        )
    }

    private func request(
        original: String = "hello",
        instruction: String = "make it formal",
        baseURL: String = "https://api.example.com/v1",
        apiKey: String = "sk-test",
        stream: Bool = false
    ) -> ChatCompletionRequest {
        ChatCompletionRequest(
            original: original,
            instruction: instruction,
            selection: selection(baseURL: baseURL),
            apiKey: apiKey,
            stream: stream
        )
    }

    // MARK: - Request building

    @Test("The request targets the provider's chat/completions endpoint")
    func endpointURL() throws {
        let built = try request().makeURLRequest()
        #expect(built.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(built.httpMethod == "POST")
        #expect(built.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("A key is sent as a bearer token, and omitted entirely when empty")
    func authorizationHeader() throws {
        let withKey = try request(apiKey: "sk-test").makeURLRequest()
        #expect(withKey.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        // Local providers (Ollama, LM Studio) need no key and can reject the header.
        let withoutKey = try request(baseURL: "http://127.0.0.1:11434/v1", apiKey: "")
            .makeURLRequest()
        #expect(withoutKey.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("An unusable base URL is rejected before any network call")
    func invalidEndpointThrows() {
        #expect(throws: AIError.self) {
            try request(baseURL: "ftp://example.com").makeURLRequest()
        }
    }

    @Test("The payload carries the model, both messages and the instruction")
    func payloadShape() throws {
        let built = try request(original: "some text", instruction: "shorten it").makeURLRequest()
        let body = try #require(built.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["model"] as? String == "gpt-4o")

        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["role"] == "user")
        #expect(messages[1]["content"]?.contains("some text") == true)
        #expect(messages[1]["content"]?.contains("shorten it") == true)
    }

    @Test("Only the streaming request sets the stream flag")
    func streamFlag() throws {
        func streamValue(_ stream: Bool) throws -> Bool? {
            let body = try #require(try request(stream: stream).makeURLRequest().httpBody)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            return json?["stream"] as? Bool
        }
        #expect(try streamValue(true) == true)
        #expect(try streamValue(false) == nil)
    }

    // MARK: - Generating with no original text

    /// The cursor-in-a-terminal case: nothing selected, the user asks for a command.
    /// Sending an empty "Original text:" block to a prompt that says "only return the
    /// rewritten text" asks a rewriter to rewrite nothing.
    @Test("With no original text the user prompt is the bare instruction")
    func generateUserPrompt() {
        let generate = request(original: "", instruction: "command to kill a process on mac")
        #expect(generate.hasOriginalText == false)
        #expect(generate.userPrompt == "command to kill a process on mac")
        #expect(generate.userPrompt.contains("Original text:") == false)
    }

    @Test("Whitespace-only original text still counts as nothing to rewrite")
    func blankOriginalIsGenerate() {
        #expect(request(original: "   \n  ").hasOriginalText == false)
    }

    @Test("The system prompt switches between rewriting and writing")
    func systemPromptSwitches() {
        #expect(request(original: "some text").systemPrompt == ChatCompletionRequest.refineSystemPrompt)
        #expect(request(original: "").systemPrompt == ChatCompletionRequest.generateSystemPrompt)
    }

    @Test("The generate prompt actually reaches the payload")
    func generatePayload() throws {
        let built = try request(original: "", instruction: "list open ports").makeURLRequest()
        let body = try #require(built.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])

        #expect(messages[0]["content"] == ChatCompletionRequest.generateSystemPrompt)
        #expect(messages[1]["content"] == "list open ports")
    }

    // MARK: - Non-streaming response

    @Test("Message content is extracted and trimmed")
    func parsesContent() {
        let body = Data(
            #"{"choices":[{"message":{"role":"assistant","content":"  Hello there.  "}}]}"#.utf8)
        #expect(ChatCompletionResponse.content(from: body) == "Hello there.")
    }

    @Test("Unexpected response shapes yield no content", arguments: [
        #"{"choices":[]}"#,
        #"{"choices":[{"message":{}}]}"#,
        #"{"unexpected":true}"#,
        "not json at all",
    ])
    func rejectsBadContent(_ body: String) {
        #expect(ChatCompletionResponse.content(from: Data(body.utf8)) == nil)
    }

    // MARK: - Streaming events

    @Test("A data line carrying content yields a delta")
    func parsesDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#
        #expect(ChatCompletionResponse.streamEvent(from: line) == .delta("Hel"))
    }

    @Test("The terminator ends the stream")
    func parsesDone() {
        #expect(ChatCompletionResponse.streamEvent(from: "data: [DONE]") == .done)
    }

    @Test("Keep-alives and contentless chunks are ignored", arguments: [
        "",
        ": keep-alive",
        #"data: {"choices":[{"delta":{}}]}"#,
        #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
        "data: not json",
    ])
    func ignoresNonContentLines(_ line: String) {
        #expect(ChatCompletionResponse.streamEvent(from: line) == .ignored)
    }

    // MARK: - Error messages

    /// The shape that previously reached the floating bar as raw JSON.
    @Test("The provider's message is lifted out of an OpenAI-style error body")
    func openAIStyleError() {
        let body = Data(
            #"{"error":{"message":"This model requires a verified organization.","type":"invalid_request_error"}}"#
                .utf8)
        #expect(
            AIError.message(fromResponseBody: body)
                == "This model requires a verified organization.")
    }

    @Test("Other common error shapes are handled", arguments: [
        (#"{"error":"Invalid API key provided"}"#, "Invalid API key provided"),
        (#"{"message":"Rate limit exceeded"}"#, "Rate limit exceeded"),
    ])
    func otherErrorShapes(_ body: String, _ expected: String) {
        #expect(AIError.message(fromResponseBody: Data(body.utf8)) == expected)
    }

    @Test("An unrecognised body is passed through rather than discarded")
    func unrecognisedErrorBody() {
        let body = #"{"detail":[{"msg":"field required"}]}"#
        #expect(AIError.message(fromResponseBody: Data(body.utf8)) == body)

        #expect(AIError.message(fromResponseBody: Data("502 Bad Gateway".utf8)) == "502 Bad Gateway")
    }

    @Test("A very long message is truncated")
    func truncatesLongMessage() {
        let long = String(repeating: "x", count: 900)
        let body = Data(#"{"error":{"message":"\#(long)"}}"#.utf8)

        let message = AIError.message(fromResponseBody: body)

        #expect(message.count == 503)  // 500 characters + the ellipsis
        #expect(message.hasSuffix("..."))
    }
}
