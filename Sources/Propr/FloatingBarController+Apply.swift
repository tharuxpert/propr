import AppKit
@preconcurrency import ApplicationServices

// Running a refine and getting the result back into the source app, by whichever
// strategy the target supports, plus undo.
extension FloatingBarController {
    // MARK: - Apply logic (smooth typing-style)

    func performRefine(context: String, snapshot: FieldSnapshot) {
        let element = applyTargetElement ?? captureCurrentFocusedElement()
        let targetPID = targetPID(from: element, fallback: applyTargetPID)
        let strategy = element == nil ? .clipboardPaste : applyStrategy

        refineTask?.cancel()

        // Identifies this request so a task that finishes late — usually because it
        // was cancelled by a newer one — cannot write its outcome over the current
        // request's state.
        refineGeneration &+= 1
        let generation = refineGeneration

        refineTask = Task { @MainActor in
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
                    // Record the whole field as it is now — value and selection — not
                    // just the text being rewritten. Undo used to write that text back
                    // over the *entire* field, so rewriting one selected word and then
                    // undoing left the field containing only the old word.
                    self.lastApplyUndo = AXTextWriter(element: element).currentState()
                        .map { .restoreField(element: element, before: $0) }
                    try await applyWithAccessibilityStreaming(
                        originalText: originalText,
                        instruction: context,
                        selection: selection,
                        apiKey: key,
                        element: element,
                        replaceSelectionOnly: hasSelection
                    )

                case .clipboardPaste:
                    // Recorded after typing, once we know what was actually typed.
                    self.lastApplyUndo = nil
                    try await applyWithClipboardPaste(
                        originalText: originalText,
                        instruction: context,
                        selection: selection,
                        apiKey: key,
                        targetPID: targetPID,
                        appName: snapshot.appName,
                        replaceExistingInput: !hasSelection && !originalText.isEmpty
                    )
                }
            } catch is CancellationError {
                // Cancelled by a newer request or by the bar closing. Only the newest
                // request may clear the spinner, otherwise a superseded task would
                // reset the UI out from under the request that replaced it.
                print("[Propr Bar] refine cancelled (generation \(generation))")
                if generation == refineGeneration {
                    sessionState.finishRequest()
                }
            } catch {
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
        selection: ModelSelection,
        apiKey: String,
        element: AXUIElement,
        replaceSelectionOnly: Bool
    ) async throws {
        let writer = AXTextWriter(element: element)
        var wroteAnything = false

        // Clears the selection (or the whole field) only once there is real text to
        // put in its place — so a reply the model marks as "cannot" leaves the user's
        // document exactly as it was.
        func write(_ text: String) async throws {
            guard !text.isEmpty else { return }
            if !wroteAnything {
                wroteAnything = true
                sessionState.startTyping()
                try writer.prepareForReplacement(
                    replacingWholeValue: !replaceSelectionOnly && !originalText.isEmpty
                )
                try? await Task.sleep(for: .milliseconds(25))
            }
            try await writer.append(text)
        }

        // Holds output back only while it could still be the "cannot" marker.
        var filter = StreamingReplyFilter()

        for try await token in AIService.shared.refineStream(
            original: originalText,
            instruction: instruction,
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
            sessionState.fail(reason)
            return
        case .text(let remaining):
            try await write(remaining)
        }

        if wroteAnything {
            sessionState.finishRequest()
        } else {
            sessionState.fail("The model returned an empty response.")
        }
    }

    func applyWithClipboardPaste(
        originalText: String,
        instruction: String,
        selection: ModelSelection,
        apiKey: String,
        targetPID: pid_t,
        appName: String,
        replaceExistingInput: Bool
    ) async throws {
        let reply = try await withTimeout(seconds: 45) {
            try await AIService.shared.refine(
                original: originalText,
                instruction: instruction,
                selection: selection,
                apiKey: apiKey
            )
        }
        try Task.checkCancellation()

        // A reply the model marks as "cannot" is a message for the user, not text for
        // their document: show it in the bar and insert nothing.
        let answer: String
        switch ModelReply.parse(reply) {
        case .cannot(let reason):
            sessionState.fail(reason)
            return
        case .text(let text):
            answer = text
        }

        guard !answer.isEmpty else {
            sessionState.fail("The model returned an empty response.")
            return
        }

        sessionState.startTyping()
        let keyboard = SourceAppKeyboard(pid: targetPID)

        // Terminals get a paste, not typing: a typed newline is Return in a shell and
        // would run each line of a multi-line answer as it was typed. Terminal applies
        // never replace anything (Propr never selects-all there), so a paste at the
        // cursor is the whole job.
        let inserted: String
        let delivered: Bool
        if TerminalApps.isTerminal(appName: appName) {
            inserted = Self.normalizingLineEndings(answer)
            delivered = await keyboard.paste(inserted)
        } else {
            inserted = answer
            delivered = await keyboard.type(answer, replacingExistingInput: replaceExistingInput)
        }
        guard delivered else { throw TextApplyError.cannotPaste }

        lastApplyUndo = .keystrokes(
            pid: targetPID,
            KeystrokeUndo.plan(
                appName: appName, insertedText: inserted, replacedExisting: replaceExistingInput)
        )
        sessionState.finishRequest()
    }

    /// `\r\n` and bare `\r` become `\n`. A shell treats a carriage return as Return, and
    /// Undo counts what was inserted — so the pasted text must contain exactly one
    /// character per line break, the same one the Backspace count assumes.
    static func normalizingLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func undoLastApply() {
        guard let undo = lastApplyUndo else {
            hide()
            return
        }
        lastApplyUndo = nil

        switch undo {
        case .restoreField(let element, let before):
            AXTextWriter(element: element).restore(before)
            // Hide after a moment so the user sees the restoration happen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                hide()
            }

        case .keystrokes(let pid, .undoShortcut):
            SourceAppKeyboard(pid: pid).sendUndo()
            hide()

        case .keystrokes(let pid, .deleteTyped(let count)):
            // Get the bar out of the way first; deleting reactivates the source app
            // and the user watches their prompt return to how it was.
            hide()
            Task { @MainActor in
                await SourceAppKeyboard(pid: pid).deleteBackward(count)
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
