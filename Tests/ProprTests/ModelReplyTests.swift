import Testing

@testable import Propr

/// A reply the model marks as "cannot" must reach the bar, never the user's document —
/// and a real answer must never lose a character along the way.
struct ModelReplyTests {

    // MARK: - Whole replies

    @Test("A marked reply is a message for the bar, carrying its reason")
    func parsesCannot() {
        #expect(
            ModelReply.parse("PROPR_CANNOT: The instruction doesn't say what to change.")
                == .cannot(reason: "The instruction doesn't say what to change."))
    }

    @Test("Ordinary replies are text, untouched")
    func parsesText() {
        #expect(ModelReply.parse("I love to eat some food") == .text("I love to eat some food"))
    }

    /// The user may genuinely ask for an apology; only the marker means "cannot".
    @Test("An apology without the marker is still an answer")
    func apologyIsText() {
        let apology = "I'm sorry for the late reply."
        #expect(ModelReply.parse(apology) == .text(apology))
    }

    @Test("Formatting a model adds around the marker is tolerated", arguments: [
        "  PROPR_CANNOT: Too vague.",
        "`PROPR_CANNOT: Too vague.`",
        "\"PROPR_CANNOT: Too vague.\"",
        "propr_cannot: Too vague.",
        "\nPROPR_CANNOT:   Too vague.  ",
    ])
    func tolerantMarker(_ reply: String) {
        #expect(ModelReply.parse(reply) == .cannot(reason: "Too vague."))
    }

    @Test("A marker with no reason still gets one")
    func emptyReason() {
        #expect(ModelReply.parse("PROPR_CANNOT:") == .cannot(reason: ModelReply.defaultReason))
    }

    @Test("The marker only counts at the start")
    func markerMidReply() {
        let text = "Use the literal PROPR_CANNOT: in your config."
        #expect(ModelReply.parse(text) == .text(text))
    }

    // MARK: - Streaming

    /// Feeds chunks through the filter; returns what would have been written, plus the
    /// final classification.
    private func stream(_ chunks: [String]) -> (written: String, end: ModelReply) {
        var filter = StreamingReplyFilter()
        var written = ""
        for chunk in chunks { written += filter.receive(chunk) }
        let end = filter.finish()
        if case .text(let rest) = end { written += rest }
        return (written, end)
    }

    @Test("A normal answer is written out in full")
    func streamsText() {
        let result = stream(["I love", " to eat", " some food"])
        #expect(result.written == "I love to eat some food")
    }

    /// "P" could be the start of the marker, so it is held for a moment — and must
    /// then be written, not dropped.
    @Test("An answer that begins like the marker loses nothing", arguments: [
        ["P", "lease find attached."],
        ["PRO", "blem solved."],
        ["PROPR", " is a menu bar app."],
    ])
    func streamsLookalikes(_ chunks: [String]) {
        #expect(stream(chunks).written == chunks.joined())
    }

    /// The reported bug: the refusal was written into the editor. Nothing may be.
    @Test("A marked reply writes nothing, even split across chunks", arguments: [
        ["PROPR_CANNOT: Too vague."],
        ["PRO", "PR_CAN", "NOT: Too", " vague."],
        ["  ", "PROPR_CANNOT:", " Too vague."],
    ])
    func streamsCannot(_ chunks: [String]) {
        let result = stream(chunks)
        #expect(result.written.isEmpty)
        #expect(result.end == .cannot(reason: "Too vague."))
    }

    @Test("Leading whitespace in a real answer is kept")
    func keepsLeadingWhitespace() {
        #expect(stream(["  ", "indented"]).written == "  indented")
    }

    @Test("A reply that ends while still ambiguous is written as text")
    func shortAmbiguousReply() {
        #expect(stream(["PROP"]).written == "PROP")
    }

    @Test("Once text starts flowing, later chunks are not held back")
    func passesThroughAfterDecision() {
        var filter = StreamingReplyFilter()
        #expect(filter.receive("Hello") == "Hello")
        #expect(filter.receive(" PROPR_CANNOT: not a refusal here") == " PROPR_CANNOT: not a refusal here")
    }

    // MARK: - Prompts

    @Test("Both prompts tell the model how to say it cannot")
    func promptsCarryMarker() {
        #expect(ChatCompletionRequest.refineSystemPrompt.contains(ModelReply.cannotMarker))
        #expect(ChatCompletionRequest.generateSystemPrompt.contains(ModelReply.cannotMarker))
    }
}

struct ModelReplyPresentationTests {
    @MainActor
    @Test("A model refusal is a notice, not an error")
    func refusalUsesNoticeState() {
        let state = FloatingBarSessionState()
        state.startRequest()

        state.showNotice("The request needs more information.")

        #expect(state.noticeMessage == "The request needs more information.")
        #expect(state.errorMessage == nil)
        #expect(!state.hasSubmitted)
        #expect(!state.isThinking)
        #expect(!state.isTyping)
    }

    @MainActor
    @Test("Starting another request clears the previous notice")
    func newRequestClearsNotice() {
        let state = FloatingBarSessionState()
        state.showNotice("The request needs more information.")

        state.startRequest()

        #expect(state.noticeMessage == nil)
        #expect(state.isThinking)
    }
}
