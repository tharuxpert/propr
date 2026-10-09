import Foundation

// Ask mode — questions about the text are answered in the bar, never in the
// document — and the session's chat history.
extension FloatingBarController {
    /// Streams the model's answer into the bar. Deliberately takes no element or pid —
    /// there is nothing here that could write to the source app.
    func answerInBar(
        originalText: String,
        question: String,
        history: [RefinementTurn],
        selection: ModelSelection,
        apiKey: String
    ) async throws {
        var reply = ""
        for try await token in AIService.shared.refineStream(
            original: originalText,
            instruction: question,
            history: history,
            selection: selection,
            apiKey: apiKey,
            intent: .ask
        ) {
            try Task.checkCancellation()
            reply += token
            sessionState.showAnswer(Self.askAnswer(from: reply), to: question, isComplete: false)
        }
        try Task.checkCancellation()

        let answer = Self.askAnswer(from: reply)
        guard !answer.isEmpty else {
            sessionState.fail("The model returned an empty response.")
            return
        }
        recordAnswer(answer, to: question)
    }

    // MARK: - Session history

    /// An edit written into the document: a turn in the chat and a step for Undo.
    func recordEdit(_ revision: AppliedRevision) {
        appliedRevisions.append(revision)
        conversation.append(revision.turn)
    }

    /// Shows a finished answer and keeps it in the chat, so the next instruction can
    /// build on it ("use that word").
    func recordAnswer(_ answer: String, to question: String) {
        sessionState.showAnswer(answer, to: question, isComplete: true)
        conversation.append(RefinementTurn(instruction: question, output: answer, kind: .answer))
    }

    /// Shows the model's reason for not acting and keeps it in the chat, so a reply
    /// such as "Spanish" to "Which language?" is understood.
    func recordCannot(_ reason: String, to instruction: String) {
        sessionState.showNotice(reason)
        conversation.append(RefinementTurn(instruction: instruction, output: reason, kind: .cannot))
    }

    /// The ask prompt does not use markers, but a model carrying habits over from
    /// earlier turns may still add one; it must not show up in the answer.
    static func askAnswer(from reply: String) -> String {
        switch ModelReply.parse(reply) {
        case .answer(let text): text
        case .cannot(let reason): reason
        case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
