import SwiftUI

// Sending a quick prompt: its text flies from the pill into the composer, is
// stamped down there, and is then sent as if it had been typed.
extension FloatingBarView {
    func sendQuickPrompt(_ quickPrompt: QuickPrompt) {
        guard let instruction = quickPrompt.instruction,
            quickPromptStamp == nil, !sessionState.isBusy
        else { return }

        // Pills show only in their own modes, so the bar's current one is always a
        // mode this prompt was offered in.
        let intent = quickPromptMode.intent

        // Without both ends of the flight, or with Reduce Motion, it just sends.
        guard !reduceMotion,
            let start = pillTextOrigins[quickPrompt.id],
            let landing = promptTextOrigin
        else {
            send(instruction, intent: intent)
            return
        }

        quickPromptStamp = QuickPromptStamp(text: instruction, start: start, landing: landing)

        Task { @MainActor in
            try? await Task.sleep(for: QuickPromptStamp.landingDelay)
            quickPromptLandings += 1

            try? await Task.sleep(for: QuickPromptStamp.settleDelay)
            // The field takes over the landed text in the same spot, and the
            // request goes out the way a typed one does.
            prompt = instruction
            quickPromptStamp = nil
            send(instruction, intent: intent)
        }
    }
}
