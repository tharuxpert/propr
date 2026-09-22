import AppKit
@preconcurrency import ApplicationServices

// Running a refine and getting the result back into the source app, by whichever
// strategy the target supports, plus undo.
extension FloatingBarController {
    // MARK: - Apply logic (smooth typing-style)

    func performRefine(context: String, snapshot: FieldSnapshot) {
        let target = capturedTargetForApply()
        let element = target.element
        let targetPID = target.pid
        let strategy = target.strategy
        let history = appliedRevisions.map(\.turn)
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
                        element: element,
                        replaceSelectionOnly: hasSelection,
                        previousRevision: previousRevision,
                        onWillWrite: {
                            pendingAXUndo = undo
                            self.lastApplyUndo = undo
                        }
                    ) {
                        let answerLength = (answer as NSString).length
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
                        let revision = AppliedRevision(
                            turn: RefinementTurn(instruction: context, output: answer),
                            undo: undo,
                            accessibilityRange: range
                        )
                        self.appliedRevisions.append(revision)
                        self.lastApplyUndo = undo
                        pendingAXUndo = nil
                        self.panel?.makeKey()
                        self.sessionState.finishRequest(appliedTurn: true)
                    }

                case .clipboardPaste:
                    if let revision = try await applyWithClipboardPaste(
                        originalText: originalText,
                        instruction: context,
                        history: history,
                        selection: selection,
                        apiKey: key,
                        targetPID: targetPID,
                        appName: snapshot.appName,
                        previousRevision: previousRevision,
                        replaceExistingInput: fallbackReplacesExistingInput
                    ) {
                        self.appliedRevisions.append(revision)
                        self.lastApplyUndo = revision.undo
                        self.panel?.makeKey()
                        self.sessionState.finishRequest(appliedTurn: true)
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

    func applyWithAccessibilityStreaming(
        originalText: String,
        instruction: String,
        history: [RefinementTurn],
        selection: ModelSelection,
        apiKey: String,
        element: AXUIElement,
        replaceSelectionOnly: Bool,
        previousRevision: AppliedRevision?,
        onWillWrite: () -> Void
    ) async throws -> String? {
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

        for try await token in AIService.shared.refineStream(
            original: originalText,
            instruction: instruction,
            history: history,
            selection: selection,
            apiKey: apiKey
        ) {
            // Throws rather than returning: a bare return here would leave the bar
            // showing "Thinking…" forever with its input disabled.
            try Task.checkCancellation()
            try await write(filter.receive(token))
        }

        switch filter.finish() {
        case .cannot(let reason):
            // The model says it can't do this. Its reason goes in the bar; nothing was
            // written to the document.
            sessionState.showNotice(reason)
            return nil
        case .text(let remaining):
            try await write(remaining)
        }

        if wroteAnything {
            return writtenText
        } else {
            sessionState.fail("The model returned an empty response.")
            return nil
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
