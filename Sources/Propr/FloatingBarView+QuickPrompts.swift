import SwiftUI

// The quick prompt pills under the bar: which show, when, and keeping the panel
// sized to them as they come and go.
extension FloatingBarView {
    /// The bar's mode, which decides which pills it offers.
    var quickPromptMode: QuickPrompt.Mode {
        sessionState.isAskMode ? .ask : .edit
    }

    /// Only with text to act on, and only the pills for `mode`.
    func quickPrompts(for mode: QuickPrompt.Mode) -> [QuickPrompt] {
        displayedContextText.isEmpty ? [] : quickPrompts.visible(in: mode)
    }

    /// Only while nothing has been typed: a pill sends its own instruction, so it
    /// would throw a typed one away. A stamp in flight sends them back too.
    var showsQuickPrompts: Bool {
        prompt.isEmpty && quickPromptStamp == nil && !quickPrompts(for: quickPromptMode).isEmpty
    }

    @ViewBuilder
    var quickPromptArea: some View {
        let prompts = quickPrompts(for: displayedQuickPromptMode)
        if !prompts.isEmpty {
            QuickPromptRow(
                prompts: prompts,
                isShown: revealsQuickPrompts,
                holdsSpace: holdsQuickPromptSpace,
                isEnabled: !sessionState.isBusy && quickPromptStamp == nil,
                glassNamespace: glassNamespace,
                onSend: sendQuickPrompt,
                onTextOriginChange: { id, origin in pillTextOrigins[id] = origin }
            )
        }
    }

    static var quickPromptAnimation: Animation {
        .spring(duration: 0.35, bounce: 0.2)
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
            displayedQuickPromptMode = quickPromptMode
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

    /// Tab swaps the set: the pills for the old mode go back into the bar and the
    /// new mode's come out. A switch that shows or hides the pills altogether is
    /// left to `quickPromptVisibilityChanged`.
    func quickPromptModeChanged() {
        guard showsQuickPrompts, displayedQuickPromptMode != quickPromptMode else { return }

        withAnimation(Self.quickPromptAnimation) { revealsQuickPrompts = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard showsQuickPrompts else { return }
            displayedQuickPromptMode = quickPromptMode
            withAnimation(Self.quickPromptAnimation) { revealsQuickPrompts = true }
        }
    }
}
