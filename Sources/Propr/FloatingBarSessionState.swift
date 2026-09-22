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

    var isBusy: Bool { isThinking || isTyping }
    var hasAppliedResult: Bool { appliedTurnCount > 0 }

    func startRequest() {
        isThinking = true
        isTyping = false
        errorMessage = nil
        noticeMessage = nil
    }

    func startTyping() {
        isThinking = false
        isTyping = true
    }

    func finishRequest(appliedTurn: Bool = false) {
        isThinking = false
        isTyping = false
        if appliedTurn {
            appliedTurnCount += 1
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
    }

    /// Shows a valid model response that should not be written into the document.
    /// This is informational, not an app or provider failure.
    func showNotice(_ message: String) {
        isThinking = false
        isTyping = false
        errorMessage = nil
        noticeMessage = message
    }

    func clearError() {
        errorMessage = nil
    }

    func clearNotice() {
        noticeMessage = nil
    }

    func rewindAppliedTurn() {
        appliedTurnCount = max(0, appliedTurnCount - 1)
        errorMessage = nil
        noticeMessage = nil
        composerRevision &+= 1
    }
}
