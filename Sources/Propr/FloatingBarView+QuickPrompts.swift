import SwiftUI

// The quick prompt pills under the bar: when they show, and keeping the panel sized
// to them as they come and go.
extension FloatingBarView {
    var visibleQuickPrompts: [QuickPrompt] {
        quickPrompts.visible
    }

    /// Only while the bar has text to act on and nothing has been typed: a pill
    /// sends its own instruction, so it would throw a typed one away.
    var showsQuickPrompts: Bool {
        !displayedContextText.isEmpty && prompt.isEmpty && !visibleQuickPrompts.isEmpty
    }

    @ViewBuilder
    var quickPromptArea: some View {
        if showsQuickPrompts {
            QuickPromptRow(
                prompts: visibleQuickPrompts,
                isEnabled: !sessionState.isBusy,
                glassNamespace: glassNamespace,
                onSend: sendQuickPrompt
            )
        } else if holdsQuickPromptSpace {
            QuickPromptRow(
                prompts: visibleQuickPrompts,
                isEnabled: false,
                glassNamespace: glassNamespace,
                isPlaceholder: true,
                onSend: { _ in }
            )
        }
    }

    func sendQuickPrompt(_ quickPrompt: QuickPrompt) {
        guard let instruction = quickPrompt.instruction else { return }
        send(instruction, intent: quickPrompt.mode.intent)
    }

    /// Grows the panel as soon as the pills appear. When they hide, the panel keeps
    /// their space until they have flowed back into the bar, then shrinks.
    func quickPromptVisibilityChanged(to shows: Bool) {
        if shows {
            holdsQuickPromptSpace = true
            onContentResize?()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !showsQuickPrompts else { return }
            holdsQuickPromptSpace = false
            onContentResize?()
        }
    }
}
