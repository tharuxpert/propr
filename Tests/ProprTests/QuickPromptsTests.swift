import Foundation
import Testing

@testable import Propr

/// Quick prompts are stored as JSON text in user defaults. These pin down the round
/// trip, the fallback for unreadable values and what the bar is allowed to show.
struct QuickPromptsTests {
    @Test("A saved list reads back unchanged")
    func roundTrip() {
        let prompts = QuickPrompts(items: [
            QuickPrompt(text: "Translate to French", mode: .edit),
            QuickPrompt(text: "Who wrote this?", mode: .ask),
        ])
        #expect(QuickPrompts(rawValue: prompts.rawValue) == prompts)
    }

    @Test("An unreadable value falls back to the defaults")
    func unreadable() {
        #expect(QuickPrompts(rawValue: "not json") == .defaults)
        #expect(QuickPrompts(rawValue: "{\"a\":1}") == .defaults)
    }

    @Test("An empty list stays empty rather than restoring the defaults")
    func emptyIsKept() {
        #expect(QuickPrompts(rawValue: "[]").items.isEmpty)
    }

    @Test("Blank prompts are hidden and the bar shows at most the limit")
    func visible() {
        let blank = QuickPrompt(text: "  \n ", mode: .ask)
        let many = (0..<10).map { QuickPrompt(text: "Prompt \($0)", mode: .edit) }
        let prompts = QuickPrompts(items: [blank] + many)

        #expect(prompts.visible.count == QuickPrompts.limit)
        #expect(prompts.visible.first?.text == "Prompt 0")
    }

    @Test("Instructions are trimmed, and each mode maps to its intent")
    func instruction() {
        #expect(QuickPrompt(text: "  Fix grammar \n", mode: .edit).instruction == "Fix grammar")
        #expect(QuickPrompt.Mode.ask.intent == .ask)
        #expect(QuickPrompt.Mode.edit.intent == .auto)
    }
}
