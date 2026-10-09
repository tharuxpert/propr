import Foundation
import Testing
@testable import Propr

struct AILookupResponseTests {
    @Test("Text answers and content parts are displayed")
    func answers() throws {
        #expect(try AILookupResponse.answer(from: Data(
            #"{"choices":[{"message":{"content":"  A brief answer.  "},"finish_reason":"stop"}]}"#.utf8
        )) == "A brief answer.")
        #expect(try AILookupResponse.answer(from: Data(
            #"{"choices":[{"message":{"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]},"finish_reason":"stop"}]}"#.utf8
        )) == "First\nSecond")
    }

    @Test("A provider error inside HTTP 200 retains its message")
    func providerError() {
        expectIssue(
            #"{"error":{"message":"This model is temporarily unavailable."}}"#,
            "Provider error: This model is temporarily unavailable.")
    }

    @Test("Empty completions explain why no answer was shown", arguments: [
        ("length", "The model hit the output-token limit before returning an answer."),
        ("content_filter", "The provider filtered the model's answer."),
        ("tool_calls", "The model returned a tool call instead of an answer. Lookup does not support tools."),
        ("stop", "The model returned an empty answer.")
    ])
    func emptyCompletion(reason: String, expected: String) {
        expectIssue(
            #"{"choices":[{"message":{"content":""},"finish_reason":"\#(reason)"}]}"#,
            expected)
    }

    @Test("Wrong endpoint and invalid JSON give actionable messages")
    func malformedResponses() {
        expectIssue(#"{"output_text":"not a chat completion"}"#,
                    "The provider didn't return chat choices. Check that this model supports the chat completions endpoint.")
        expectIssue("<html>Gateway error</html>",
                    "The provider returned a response that wasn't valid JSON.")
    }

    @Test("A refusal is shown as the model's reply")
    func refusal() throws {
        let body = #"{"choices":[{"message":{"content":null,"refusal":"I can't answer that."},"finish_reason":"stop"}]}"#
        #expect(try AILookupResponse.answer(from: Data(body.utf8)) == "I can't answer that.")
    }

    private func expectIssue(_ body: String, _ expected: String) {
        do {
            _ = try AILookupResponse.answer(from: Data(body.utf8))
            Issue.record("Expected a lookup response issue")
        } catch {
            #expect(error.localizedDescription == expected)
        }
    }
}
