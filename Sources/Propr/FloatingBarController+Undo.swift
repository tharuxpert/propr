import AppKit

// Rewinds one document revision and the matching conversation turn without closing
// the floating session.
extension FloatingBarController {
    func undoLastApply() {
        guard let revision = appliedRevisions.last else { return }
        refineTask?.cancel()

        Task { @MainActor in
            do {
                try await applyUndo(revision.undo)
                appliedRevisions.removeLast()
                // The chat rewinds with the document: the undone edit and anything
                // asked about it afterwards no longer describe the text.
                if let index = conversation.lastIndex(of: revision.turn) {
                    conversation.removeSubrange(index...)
                }
                lastApplyUndo = appliedRevisions.last?.undo

                // Keyboard fallbacks temporarily reactivate the source app. Bring the
                // still-open refinement session back so the next follow-up is ready.
                panel?.makeKey()
                sessionState.rewindAppliedTurn(to: appliedRevisions.last?.turn.output)
            } catch {
                sessionState.fail(error.localizedDescription)
            }
        }
    }

    func applyUndo(_ undo: ApplyUndo) async throws {
        switch undo {
        case .restoreField(let element, let before):
            AXTextWriter(element: element).restore(before)

        case .keystrokes(let pid, let keystrokeUndo, let cursorTrailingCharacters):
            await reverseKeystrokeApply(
                pid: pid,
                undo: keystrokeUndo,
                cursorTrailingCharacters: cursorTrailingCharacters)

        case .restorePreviousKeystrokes(
            let pid,
            let removeCurrent,
            let currentCursorTrailingCharacters,
            let previousText,
            let previousCursorTrailingCharacters,
            let replacingExistingInput,
            let appName
        ):
            await reverseKeystrokeApply(
                pid: pid,
                undo: removeCurrent,
                cursorTrailingCharacters: currentCursorTrailingCharacters)
            guard
                await deliverFallbackText(
                    previousText,
                    pid: pid,
                    appName: appName,
                    replacingExistingInput: replacingExistingInput
                )
            else {
                throw TextApplyError.cannotPaste
            }
            await placeFallbackCaret(
                trailingCharacters: previousCursorTrailingCharacters,
                pid: pid)
        }
    }
}
