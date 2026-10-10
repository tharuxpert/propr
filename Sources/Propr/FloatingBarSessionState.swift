import AppKit
import SwiftUI

@MainActor
final class FloatingBarSessionState: ObservableObject {
    @Published var isThinking = false
    @Published var isTyping = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var appliedTurnCount = 0
    @Published private(set) var composerRevision = 0
    @Published private(set) var latestAppliedText: String?
    /// An answer shown in the bar instead of being written into the document.
    @Published private(set) var answer: Answer?
    /// Ask mode: every request is answered in the bar. Toggled with Tab.
    @Published var isAskMode = false

    struct Answer: Equatable {
        /// The instruction that produced it, so it can be retried as an edit.
        let question: String
        var text: String
        var isComplete: Bool
    }

    var isBusy: Bool { isThinking || isTyping }
    var hasAppliedResult: Bool { appliedTurnCount > 0 }

    func startRequest() {
        isThinking = true
        isTyping = false
        errorMessage = nil
        noticeMessage = nil
        answer = nil
    }

    /// Updates the answer as it streams in. `isComplete` ends the request.
    func showAnswer(_ text: String, to question: String, isComplete: Bool) {
        answer = Answer(question: question, text: text, isComplete: isComplete)
        if isComplete {
            isThinking = false
            isTyping = false
            composerRevision &+= 1
        }
    }


    func startTyping() {
        isThinking = false
        isTyping = true
    }

    func finishRequest(appliedText: String? = nil) {
        isThinking = false
        isTyping = false
        if let appliedText {
            appliedTurnCount += 1
            latestAppliedText = appliedText
            composerRevision &+= 1
        }
    }

    func stopTyping() {
        isTyping = false
    }

    func fail(_ message: String) {
        isThinking = false
        isTyping = false
        errorMessage = message
        noticeMessage = nil
        answer = nil
    }

    /// Shows a valid model response that should not be written into the document.
    /// This is informational, not an app or provider failure.
    func showNotice(_ message: String) {
        isThinking = false
        isTyping = false
        errorMessage = nil
        noticeMessage = message
        answer = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        noticeMessage = nil
    }

    func rewindAppliedTurn(to previousText: String?) {
        appliedTurnCount = max(0, appliedTurnCount - 1)
        latestAppliedText = previousText
        errorMessage = nil
        noticeMessage = nil
        composerRevision &+= 1
    }
}
