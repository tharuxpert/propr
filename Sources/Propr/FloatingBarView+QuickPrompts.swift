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
                isShown: revealsQuickPrompts,
                holdsSpace: holdsQuickPromptSpace,
                isEnabled: !sessionState.isBusy,
                glassNamespace: glassNamespace,
                onSend: sendQuickPrompt
            )
        }
    }

    static var quickPromptAnimation: Animation {
        .spring(duration: 0.35, bounce: 0.2)
    }

    func sendQuickPrompt(_ quickPrompt: QuickPrompt) {
        guard let instruction = quickPrompt.instruction else { return }
        send(instruction, intent: quickPrompt.mode.intent)
    }

    /// The panel only grows a pass after the content does, so pills animated out at
    /// once would start below its bottom edge, cut off, and pop into view halfway.
    /// They wait for the room first. On the way back the room is kept until they
    /// are in, so the panel does not shrink under them.
    ///
    /// Only the reveal is animated, which keeps the spring off the rest of the bar.
    func quickPromptVisibilityChanged(to shows: Bool) {
        if shows {
            holdsQuickPromptSpace = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                guard showsQuickPrompts else { return }
                withAnimation(Self.quickPromptAnimation) { revealsQuickPrompts = true }
            }
            return
        }

        withAnimation(Self.quickPromptAnimation) { revealsQuickPrompts = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !showsQuickPrompts else { return }
            holdsQuickPromptSpace = false
        }
    }
}
