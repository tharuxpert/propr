import AppKit
import SwiftUI

@MainActor
final class FloatingBarSessionState: ObservableObject {
    @Published var hasSubmitted = false
    @Published var isThinking = false
    @Published var isTyping = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    func startRequest() {
        hasSubmitted = true
        isThinking = true
        isTyping = false
        errorMessage = nil
        noticeMessage = nil
    }

    func startTyping() {
        isThinking = false
        isTyping = true
    }

    func finishRequest() {
        isThinking = false
        isTyping = false
    }

    func stopTyping() {
        isTyping = false
    }

    func fail(_ message: String) {
        hasSubmitted = false
        isThinking = false
        isTyping = false
        errorMessage = message
        noticeMessage = nil
    }

    /// Shows a valid model response that should not be written into the document.
    /// This is informational, not an app or provider failure.
    func showNotice(_ message: String) {
        hasSubmitted = false
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
}
