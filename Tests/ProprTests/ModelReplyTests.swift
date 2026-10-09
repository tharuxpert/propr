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

    // MARK: - Answers

    @Test("An answer-marked reply is an answer for the bar")
    func parsesAnswer() {
        #expect(
            ModelReply.parse("PROPR_ANSWER: It means \"to find\".")
                == .answer("It means \"to find\"."))
    }

    @Test("A multi-line answer keeps its lines")
    func multiLineAnswer() {
        #expect(ModelReply.parse("PROPR_ANSWER:\nYes.\nBut check the comma.") == .answer("Yes.\nBut check the comma."))
    }

    /// The whole point: a question must never touch the user's text, even when the
    /// marker arrives in pieces.
    @Test("An answer writes nothing to the document, even split across chunks", arguments: [
        ["PROPR_ANSWER: No, ", "it should be \"do\"."],
        ["PRO", "PR_ANS", "WER: No, it should", " be \"do\"."],
        ["`", "PROPR_ANSWER:", " No, it should be \"do\"."],
    ])
    func streamsAnswer(_ chunks: [String]) {
        let result = stream(chunks)
        #expect(result.written.isEmpty)
        #expect(result.end == .answer("No, it should be \"do\"."))
    }

    @Test("The answer is readable while it streams")
    func partialAnswer() {
        var filter = StreamingReplyFilter()
        #expect(filter.receive("PROPR_ANS") == "")
        #expect(filter.partialAnswer == nil)
        #expect(filter.receive("WER: It means") == "")
        #expect(filter.partialAnswer == "It means")
    }

    @Test("Text that only starts like the answer marker is written in full", arguments: [
        ["PROPR_A", "pp settings"],
        ["PROPR_", "CAN be configured"],
    ])
    func answerLookalikes(_ chunks: [String]) {
        #expect(stream(chunks).written == chunks.joined())
    }

    @Test("Ask mode strips a stray marker from the answer")
    @MainActor
    func askAnswerStripsMarker() {
        #expect(FloatingBarController.askAnswer(from: "PROPR_ANSWER: Yes.") == "Yes.")
        #expect(FloatingBarController.askAnswer(from: "  Yes.\n") == "Yes.")
    }

    // MARK: - Cursor placement

    @Test("The cursor marker is removed and its UTF-16 position is preserved")
    func parsesCursorMarker() {
        let parsed = CursorMarkedText.parse("git commit -m '<PROPR_CURSOR>'")

        #expect(parsed.text == "git commit -m ''")
        #expect(parsed.cursorUTF16Offset == "git commit -m '".utf16.count)
        #expect(parsed.trailingCharacterCount == 1)
    }

    @Test("Text without a cursor marker is unchanged")
    func cursorMarkerIsOptional() {
        let parsed = CursorMarkedText.parse("git status")
        #expect(parsed == CursorMarkedText(text: "git status", cursorUTF16Offset: nil))
        #expect(parsed.trailingCharacterCount == 0)
    }

    @Test("An empty single-quoted slot gets a fallback cursor")
    func infersCursorInEmptySingleQuotes() {
        let parsed = CursorMarkedText.parse("git commit -m ''")

        #expect(parsed.text == "git commit -m ''")
        #expect(parsed.cursorUTF16Offset == "git commit -m '".utf16.count)
        #expect(parsed.trailingCharacterCount == 1)
    }

    @Test("An empty double-quoted slot gets a fallback cursor")
    func infersCursorInEmptyDoubleQuotes() {
        let parsed = CursorMarkedText.parse("printf \"\"")

        #expect(parsed.text == "printf \"\"")
        #expect(parsed.cursorUTF16Offset == "printf \"".utf16.count)
        #expect(parsed.trailingCharacterCount == 1)
    }

    @Test("A Unicode prefix uses the Accessibility API's UTF-16 coordinates")
    func cursorOffsetUsesUTF16() {
        let parsed = CursorMarkedText.parse("👋🏽 <PROPR_CURSOR>done")
        #expect(parsed.cursorUTF16Offset == "👋🏽 ".utf16.count)
        #expect(parsed.trailingCharacterCount == 4)
    }

    @Test("A cursor marker split across stream chunks is never written")
    func streamsCursorMarker() {
        var filter = StreamingCursorMarkerFilter()
        var written = ""
        for chunk in ["git commit -m '<PRO", "PR_CUR", "SOR>", "'"] {
            written += filter.receive(chunk)
        }
        written += filter.finish()

        #expect(written == "git commit -m ''")
        #expect(filter.cursorUTF16Offset == "git commit -m '".utf16.count)
    }

    @Test("An incomplete cursor-marker lookalike remains literal text")
    func streamsCursorMarkerLookalike() {
        var filter = StreamingCursorMarkerFilter()
        var written = filter.receive("Use <PROPR_CUR")
        written += filter.finish()
        #expect(written == "Use <PROPR_CUR")
        #expect(filter.cursorUTF16Offset == nil)
    }

    // MARK: - Prompts

    @Test("Both prompts tell the model how to say it cannot")
    func promptsCarryMarker() {
        #expect(ChatCompletionRequest.refineSystemPrompt.contains(ModelReply.cannotMarker))
        #expect(ChatCompletionRequest.generateSystemPrompt.contains(ModelReply.cannotMarker))
    }

    @Test("Both prompts explain the optional cursor marker")
    func promptsCarryCursorMarker() {
        #expect(ChatCompletionRequest.refineSystemPrompt.contains(CursorMarkedText.marker))
        #expect(ChatCompletionRequest.generateSystemPrompt.contains(CursorMarkedText.marker))
        #expect(ChatCompletionRequest.cursorInstruction.contains("at most once"))
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
        #expect(!state.hasAppliedResult)
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

    @MainActor
    @Test("Completed turns keep the composer available and can be rewound")
    func completedTurnsAndUndo() {
        let state = FloatingBarSessionState()

        state.startRequest()
        state.startTyping()
        state.finishRequest(appliedText: "First result")

        #expect(state.hasAppliedResult)
        #expect(state.appliedTurnCount == 1)
        #expect(state.latestAppliedText == "First result")
        #expect(!state.isBusy)

        state.startRequest()
        state.finishRequest(appliedText: "Second result")
        #expect(state.appliedTurnCount == 2)
        #expect(state.latestAppliedText == "Second result")

        state.rewindAppliedTurn(to: "First result")
        #expect(state.appliedTurnCount == 1)
        #expect(state.hasAppliedResult)
        #expect(state.latestAppliedText == "First result")

        state.rewindAppliedTurn(to: nil)
        #expect(state.appliedTurnCount == 0)
        #expect(!state.hasAppliedResult)
        #expect(state.latestAppliedText == nil)
    }

    @MainActor
    @Test("A failed follow-up keeps the earlier successful turn undoable")
    func failedFollowUpKeepsHistory() {
        let state = FloatingBarSessionState()
        state.startRequest()
        state.finishRequest(appliedText: "First result")

        state.startRequest()
        state.fail("Provider unavailable")

        #expect(state.appliedTurnCount == 1)
        #expect(state.hasAppliedResult)
        #expect(state.latestAppliedText == "First result")
        #expect(state.errorMessage == "Provider unavailable")
        #expect(!state.isBusy)
    }
}
