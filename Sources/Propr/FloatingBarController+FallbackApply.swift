import AppKit

// Non-AX application of completed model replies. Unlike the AX path this cannot
// stream safely, so it waits for a complete answer before touching the source app.
extension FloatingBarController {
    func applyWithClipboardPaste(
        originalText: String,
        instruction: String,
        history: [RefinementTurn],
        selection: ModelSelection,
        apiKey: String,
        intent: RefineIntent,
        targetPID: pid_t,
        appName: String,
        previousRevision: AppliedRevision?,
        replaceExistingInput: Bool
    ) async throws -> AppliedRevision? {
        let reply = try await withTimeout(seconds: 45) {
            try await AIService.shared.refine(
                original: originalText,
                instruction: instruction,
                history: history,
                selection: selection,
                apiKey: apiKey,
                intent: intent
            )
        }
        try Task.checkCancellation()

        let rawAnswer: String
        switch ModelReply.parse(reply) {
        case .cannot(let reason):
            recordCannot(reason, to: instruction)
            return nil
        case .answer(let answer):
            recordAnswer(answer, to: instruction)
            return nil
        case .text(let text):
            rawAnswer = text
        }

        let normalizedAnswer = TerminalApps.isTerminal(appName: appName)
            ? Self.normalizingLineEndings(rawAnswer) : rawAnswer
        let answer = CursorMarkedText.parse(normalizedAnswer)

        guard !answer.text.isEmpty else {
            sessionState.fail("The model returned an empty response.")
            return nil
        }

        if let previousRevision {
            let removePrevious = KeystrokeUndo.plan(
                appName: appName,
                insertedText: previousRevision.turn.output,
                replacedExisting: replaceExistingInput
            )
            await reverseKeystrokeApply(
                pid: targetPID,
                undo: removePrevious,
                cursorTrailingCharacters: previousRevision.cursorTrailingCharacterCount
            )
        }

        sessionState.startTyping()
        let delivered = await deliverFallbackText(
                answer.text,
                pid: targetPID,
                appName: appName,
                replacingExistingInput: replaceExistingInput
            )
        guard delivered else {
            // The previous revision was already unwound. Best-effort restoration keeps
            // a failed follow-up from silently deleting the last successful answer.
            if let previousRevision {
                _ = await Task { @MainActor in
                    await self.restoreFallbackRevision(
                        previousRevision,
                        pid: targetPID,
                        appName: appName,
                        replacingExistingInput: replaceExistingInput)
                }.value
            }
            try Task.checkCancellation()
            throw TextApplyError.cannotPaste
        }

        let removeCurrent = KeystrokeUndo.plan(
            appName: appName,
            insertedText: answer.text,
            replacedExisting: replaceExistingInput
        )
        await placeFallbackCaret(
            trailingCharacters: answer.trailingCharacterCount,
            pid: targetPID)

        do {
            try Task.checkCancellation()
        } catch {
            // Cursor placement completes in an uncancelled child task, so the current
            // result can be removed safely even if Stop was clicked at the last moment.
            await Task { @MainActor in
                await self.reverseKeystrokeApply(
                    pid: targetPID,
                    undo: removeCurrent,
                    cursorTrailingCharacters: answer.trailingCharacterCount)
                if let previousRevision {
                    _ = await self.restoreFallbackRevision(
                        previousRevision,
                        pid: targetPID,
                        appName: appName,
                        replacingExistingInput: replaceExistingInput)
                }
            }.value
            throw error
        }

        let undo: ApplyUndo
        if let previousRevision {
            undo = .restorePreviousKeystrokes(
                pid: targetPID,
                removeCurrent: removeCurrent,
                currentCursorTrailingCharacters: answer.trailingCharacterCount,
                previousText: previousRevision.turn.output,
                previousCursorTrailingCharacters: previousRevision.cursorTrailingCharacterCount,
                replacingExistingInput: replaceExistingInput,
                appName: appName
            )
        } else {
            undo = .keystrokes(
                pid: targetPID,
                removeCurrent,
                cursorTrailingCharacters: answer.trailingCharacterCount)
        }

        return AppliedRevision(
            turn: RefinementTurn(instruction: instruction, output: answer.text),
            undo: undo,
            accessibilityRange: nil,
            cursorUTF16Offset: answer.cursorUTF16Offset
        )
    }

    /// `\r\n` and bare `\r` become `\n`. A shell treats a carriage return as Return, and
    /// Undo counts what was inserted — so the pasted text must contain exactly one
    /// character per line break, the same one the Backspace count assumes.
    static func normalizingLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func reverseKeystrokeApply(
        pid: pid_t,
        undo: KeystrokeUndo,
        cursorTrailingCharacters: Int = 0
    ) async {
        let keyboard = SourceAppKeyboard(pid: pid)
        switch undo {
        case .undoShortcut:
            keyboard.sendUndo()
            try? await Task.sleep(for: .milliseconds(160))
        case .deleteTyped(let count):
            _ = await keyboard.moveCaretRight(cursorTrailingCharacters)
            await keyboard.deleteBackward(count)
        }
    }

    func placeFallbackCaret(trailingCharacters: Int, pid: pid_t) async {
        guard trailingCharacters > 0 else { return }
        let moved = await Task { @MainActor in
            await SourceAppKeyboard(pid: pid).moveCaretLeft(trailingCharacters)
        }.value
        if !moved {
            print("[Propr Bar] Could not place fallback caret inside generated text")
        }
    }

    func restoreFallbackRevision(
        _ revision: AppliedRevision,
        pid: pid_t,
        appName: String,
        replacingExistingInput: Bool
    ) async -> Bool {
        let restored = await deliverFallbackText(
            revision.turn.output,
            pid: pid,
            appName: appName,
            replacingExistingInput: replacingExistingInput)
        if restored {
            await placeFallbackCaret(
                trailingCharacters: revision.cursorTrailingCharacterCount,
                pid: pid)
        }
        return restored
    }

    func deliverFallbackText(
        _ text: String,
        pid: pid_t,
        appName: String,
        replacingExistingInput: Bool
    ) async -> Bool {
        let keyboard = SourceAppKeyboard(pid: pid)
        if TerminalApps.isTerminal(appName: appName) {
            return await keyboard.paste(text)
        }
        return await keyboard.type(text, replacingExistingInput: replacingExistingInput)
    }
}
