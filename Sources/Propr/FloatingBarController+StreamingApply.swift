import AppKit
@preconcurrency import ApplicationServices

// The Accessibility write path: streams the reply straight into the focused field.
extension FloatingBarController {
    func applyWithAccessibilityStreaming(
        originalText: String,
        instruction: String,
        history: [RefinementTurn],
        selection: ModelSelection,
        apiKey: String,
        intent: RefineIntent,
        element: AXUIElement,
        replaceSelectionOnly: Bool,
        previousRevision: AppliedRevision?,
        onWillWrite: () -> Void
    ) async throws -> CursorMarkedText? {
        let writer = AXTextWriter(element: element)
        var wroteAnything = false
        var writtenText = ""

        // Clears the selection (or the whole field) only once there is real text to
        // put in its place — so a reply the model marks as "cannot" leaves the user's
        // document exactly as it was.
        func write(_ text: String) async throws {
            guard !text.isEmpty else { return }
            if !wroteAnything {
                wroteAnything = true
                sessionState.startTyping()
                onWillWrite()
                if let previousRevision,
                    let range = previousRevision.accessibilityRange
                {
                    try writer.selectPreviouslyAppliedText(
                        previousRevision.turn.output,
                        range: range
                    )
                }
                try writer.prepareForReplacement(
                    replacingWholeValue: previousRevision == nil
                        && !replaceSelectionOnly && !originalText.isEmpty
                )
                try? await Task.sleep(for: .milliseconds(25))
            }
            try await writer.append(text)
            writtenText += text
        }

        // Holds output back only while it could still be the "cannot" marker.
        var filter = StreamingReplyFilter()
        // Independently holds a possible cursor marker so none of it is ever typed.
        var cursorFilter = StreamingCursorMarkerFilter()

        for try await token in AIService.shared.refineStream(
            original: originalText,
            instruction: instruction,
            history: history,
            selection: selection,
            apiKey: apiKey,
            intent: intent
        ) {
            // Throws rather than returning: a bare return here would leave the bar
            // showing "Thinking…" forever with its input disabled.
            try Task.checkCancellation()
            try await write(cursorFilter.receive(filter.receive(token)))
            if let partial = filter.partialAnswer {
                sessionState.showAnswer(partial, to: instruction, isComplete: false)
            }
        }

        // Cancelling an AsyncThrowingStream can end iteration without throwing.
        // Treat that as cancellation before an empty or partial reply is validated.
        try Task.checkCancellation()

        switch filter.finish() {
        case .cannot(let reason):
            // The model says it can't do this. Its reason goes in the bar; nothing was
            // written to the document.
            sessionState.showNotice(reason)
            return nil
        case .answer(let answer):
            // A question about the text. The answer goes in the bar; nothing was
            // written to the document.
            sessionState.showAnswer(answer, to: instruction, isComplete: true)
            return nil
        case .text(let remaining):
            try await write(cursorFilter.receive(remaining))
        }
        try await write(cursorFilter.finish())

        if wroteAnything {
            return CursorMarkedText(
                text: writtenText,
                cursorUTF16Offset: cursorFilter.cursorUTF16Offset
            )
        } else {
            sessionState.fail("The model returned an empty response.")
            return nil
        }
    }
}
