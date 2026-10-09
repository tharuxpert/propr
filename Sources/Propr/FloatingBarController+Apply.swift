import AppKit
@preconcurrency import ApplicationServices

// Running a refine and getting the result back into the source app, by whichever
// strategy the target supports, plus undo.
extension FloatingBarController {
    // MARK: - Apply logic (smooth typing-style)

    func stopRefine() {
        guard sessionState.isBusy else { return }
        refineTask?.cancel()
    }

    func performRefine(context: String, snapshot: FieldSnapshot, intent: RefineIntent = .auto) {
        let target = capturedTargetForApply()
        let element = target.element
        let targetPID = target.pid
        let strategy = target.strategy
        let history = conversation
        let previousRevision = appliedRevisions.last

        refineTask?.cancel()

        // Identifies this request so a task that finishes late — usually because it
        // was cancelled by a newer one — cannot write its outcome over the current
        // request's state.
        refineGeneration &+= 1
        let generation = refineGeneration

        refineTask = Task { @MainActor in
            var pendingAXUndo: ApplyUndo?
            do {
                guard let selection = ModelStore.shared.selectedModel() else {
                    sessionState.fail("No model selected. Add one in Settings.")
                    return
                }

                let key = ModelStore.shared.apiKey(for: selection.endpointID) ?? ""
                if selection.requiresAPIKey
                    && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    sessionState.fail(
                        "No API key found for the selected model. Add it in Settings.")
                    return
                }

                let selectedText =
                    snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : ""
                let hasSelection = !selectedText.isEmpty
                let originalText = sanitizedModelContext(
                    hasSelection ? selectedText : snapshot.fullText)

                // Ask mode never reaches the write paths below, so the source app's
                // text, selection and clipboard cannot be touched whatever the reply.
                if intent == .ask {
                    try await answerInBar(
                        originalText: originalText,
                        question: context,
                        history: history,
                        selection: selection,
                        apiKey: key
                    )
                    return
                }

                switch strategy {
                case .accessibility:
                    guard let element else {
                        throw TextApplyError.cannotWriteAX
                    }
                    let writer = AXTextWriter(element: element)
                    guard let before = writer.currentState() else {
                        throw TextApplyError.cannotWriteAX
                    }
                    let undo = ApplyUndo.restoreField(element: element, before: before)
                    let previousRange = previousRevision?.accessibilityRange
                    let insertionLocation: Int
                    if let previousRange {
                        insertionLocation = previousRange.location
                    } else if !hasSelection && !originalText.isEmpty {
                        insertionLocation = 0
                    } else {
                        insertionLocation = before.selectedRange?.location
                            ?? (before.value as NSString).length
                    }

                    if let answer = try await applyWithAccessibilityStreaming(
                        originalText: originalText,
                        instruction: context,
                        history: history,
                        selection: selection,
                        apiKey: key,
                        intent: intent,
                        element: element,
                        replaceSelectionOnly: hasSelection,
                        previousRevision: previousRevision,
                        onWillWrite: {
                            pendingAXUndo = undo
                            self.lastApplyUndo = undo
                        }
                    ) {
                        let answerLength = (answer.text as NSString).length
                        let finalSelection = writer.currentState()?.selectedRange
                        let appliedLocation: Int
                        if let finalSelection, finalSelection.length == answerLength {
                            appliedLocation = finalSelection.location
                        } else if let finalSelection, finalSelection.length == 0,
                            finalSelection.location >= answerLength
                        {
                            appliedLocation = finalSelection.location - answerLength
                        } else {
                            appliedLocation = insertionLocation
                        }
                        let range = CFRange(
                            location: appliedLocation,
                            length: answerLength
                        )
                        if let cursorOffset = answer.cursorUTF16Offset {
                            try? writer.placeCaret(
                                atUTF16Offset: appliedLocation + cursorOffset)
                        }
                        let revision = AppliedRevision(
                            turn: RefinementTurn(instruction: context, output: answer.text),
                            undo: undo,
                            accessibilityRange: range,
                            cursorUTF16Offset: answer.cursorUTF16Offset
                        )
                        self.recordEdit(revision)
                        self.lastApplyUndo = undo
                        pendingAXUndo = nil
                        self.panel?.makeKey()
                        self.sessionState.finishRequest(appliedText: answer.text)
                    }

                case .clipboardPaste:
                    if let revision = try await applyWithClipboardPaste(
                        originalText: originalText,
                        instruction: context,
                        history: history,
                        selection: selection,
                        apiKey: key,
                        intent: intent,
                        targetPID: targetPID,
                        appName: snapshot.appName,
                        previousRevision: previousRevision,
                        replaceExistingInput: fallbackReplacesExistingInput
                    ) {
                        self.recordEdit(revision)
                        self.lastApplyUndo = revision.undo
                        self.panel?.makeKey()
                        self.sessionState.finishRequest(appliedText: revision.turn.output)
                    }
                }
            } catch is CancellationError {
                if let pendingAXUndo {
                    try? await applyUndo(pendingAXUndo)
                    lastApplyUndo = isVisible ? previousRevision?.undo : nil
                }
                // Cancelled by a newer request or by the bar closing. Only the newest
                // request may clear the spinner, otherwise a superseded task would
                // reset the UI out from under the request that replaced it.
                print("[Propr Bar] refine cancelled (generation \(generation))")
                if generation == refineGeneration {
                    sessionState.finishRequest()
                }
            } catch {
                if let pendingAXUndo {
                    try? await applyUndo(pendingAXUndo)
                    lastApplyUndo = previousRevision?.undo
                }
                print("AI refinement failed: \(error)")
                if generation == refineGeneration {
                    sessionState.fail(error.localizedDescription)
                }
                // Never write error text into the target application
            }
        }
    }

    func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TextApplyError.requestTimedOut
            }

            guard let result = try await group.next() else {
                throw TextApplyError.requestTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    func sanitizedModelContext(_ text: String) -> String {
        let maxContextCharacters = 8_000
        guard text.count > maxContextCharacters else { return text }
        print("[Propr Bar] Dropping oversized context (\(text.count) chars)")
        return ""
    }

}
