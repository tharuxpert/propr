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
                apiKey: apiKey
            )
        }
        try Task.checkCancellation()

        let answer: String
        switch ModelReply.parse(reply) {
        case .cannot(let reason):
            sessionState.showNotice(reason)
            return nil
        case .text(let text):
            answer = text
        }

        guard !answer.isEmpty else {
            sessionState.fail("The model returned an empty response.")
            return nil
        }

        let inserted = TerminalApps.isTerminal(appName: appName)
            ? Self.normalizingLineEndings(answer) : answer

        if let previousRevision {
            let removePrevious = KeystrokeUndo.plan(
                appName: appName,
                insertedText: previousRevision.turn.output,
                replacedExisting: replaceExistingInput
            )
            await reverseKeystrokeApply(pid: targetPID, undo: removePrevious)
        }

        sessionState.startTyping()
        guard
            await deliverFallbackText(
                inserted,
                pid: targetPID,
                appName: appName,
                replacingExistingInput: replaceExistingInput
            )
        else {
            // The previous revision was already unwound. Best-effort restoration keeps
            // a failed follow-up from silently deleting the last successful answer.
            if let previousRevision {
                _ = await deliverFallbackText(
                    previousRevision.turn.output,
                    pid: targetPID,
                    appName: appName,
                    replacingExistingInput: replaceExistingInput
                )
            }
            throw TextApplyError.cannotPaste
        }

        let removeCurrent = KeystrokeUndo.plan(
            appName: appName,
            insertedText: inserted,
            replacedExisting: replaceExistingInput
        )
        let undo: ApplyUndo
        if let previousRevision {
            undo = .restorePreviousKeystrokes(
                pid: targetPID,
                removeCurrent: removeCurrent,
                previousText: previousRevision.turn.output,
                replacingExistingInput: replaceExistingInput,
                appName: appName
            )
        } else {
            undo = .keystrokes(pid: targetPID, removeCurrent)
        }

        return AppliedRevision(
            turn: RefinementTurn(instruction: instruction, output: inserted),
            undo: undo,
            accessibilityRange: nil
        )
    }

    /// `\r\n` and bare `\r` become `\n`. A shell treats a carriage return as Return, and
    /// Undo counts what was inserted — so the pasted text must contain exactly one
    /// character per line break, the same one the Backspace count assumes.
    static func normalizingLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func reverseKeystrokeApply(pid: pid_t, undo: KeystrokeUndo) async {
        let keyboard = SourceAppKeyboard(pid: pid)
        switch undo {
        case .undoShortcut:
            keyboard.sendUndo()
            try? await Task.sleep(for: .milliseconds(160))
        case .deleteTyped(let count):
            await keyboard.deleteBackward(count)
        }
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
