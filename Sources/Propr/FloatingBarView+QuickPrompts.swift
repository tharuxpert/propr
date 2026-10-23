import SwiftUI

// The quick prompt pills under the bar: when they show, and keeping the panel sized
// to them as they come and go.
extension FloatingBarView {
    var visibleQuickPrompts: [QuickPrompt] {
        quickPrompts.visible
    }

    /// Whether the bar offers pills at all: only with text to act on.
    var hasQuickPrompts: Bool {
        !displayedContextText.isEmpty && !visibleQuickPrompts.isEmpty
    }

    /// Only while nothing has been typed: a pill sends its own instruction, so it
    /// would throw a typed one away.
    var showsQuickPrompts: Bool {
        hasQuickPrompts && prompt.isEmpty
    }

    @ViewBuilder
    var quickPromptArea: some View {
        if hasQuickPrompts {
            QuickPromptRow(
                prompts: visibleQuickPrompts,
                isShown: showsQuickPrompts,
                holdsSpace: holdsQuickPromptSpace,
                isEnabled: !sessionState.isBusy,
                glassNamespace: glassNamespace,
                onSend: sendQuickPrompt
            )
            .animation(Self.quickPromptAnimation, value: showsQuickPrompts)
        }
    }

    static var quickPromptAnimation: Animation {
        .spring(duration: 0.35, bounce: 0.2)
    }

    func sendQuickPrompt(_ quickPrompt: QuickPrompt) {
        guard let instruction = quickPrompt.instruction else { return }
        send(instruction, intent: quickPrompt.mode.intent)
    }

    /// The row takes its space as soon as the pills show. When they hide it keeps
    /// it until they are back under the bar, so the panel does not shrink under
    /// them mid-animation.
    func quickPromptVisibilityChanged(to shows: Bool) {
        if shows {
            holdsQuickPromptSpace = true
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !showsQuickPrompts else { return }
            holdsQuickPromptSpace = false
        }
    }
}
