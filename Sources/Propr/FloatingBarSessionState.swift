import AppKit
import SwiftUI

@MainActor
final class FloatingBarSessionState: ObservableObject {
    @Published var hasSubmitted = false
    @Published var isThinking = false
    @Published var isTyping = false
    @Published var errorMessage: String?

    func startRequest() {
        hasSubmitted = true
        isThinking = true
        isTyping = false
        errorMessage = nil
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
    }

    func clearError() {
        errorMessage = nil
    }
}

