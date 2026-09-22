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

    func rewindAppliedTurn(to previousText: String?) {
        appliedTurnCount = max(0, appliedTurnCount - 1)
        latestAppliedText = previousText
        errorMessage = nil
        noticeMessage = nil
        composerRevision &+= 1
    }
}
