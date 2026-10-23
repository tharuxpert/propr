import Foundation
import Testing

@testable import Propr

/// Quick prompts are stored as JSON text in user defaults. These pin down the round
/// trip, the fallback for unreadable values and what the bar is allowed to show.
struct QuickPromptsTests {
    @Test("A saved list reads back unchanged")
    func roundTrip() {
        let prompts = QuickPrompts(items: [
            QuickPrompt(text: "Translate to French", modes: [.edit]),
            QuickPrompt(text: "Who wrote this?", modes: [.ask]),
            QuickPrompt(text: "Summarize", modes: [.ask, .edit]),
        ])
        #expect(QuickPrompts(rawValue: prompts.rawValue) == prompts)
    }

    @Test("A list saved with one mode per prompt still reads")
    func singleModeList() {
        let id = UUID()
        let stored = "[{\"id\":\"\(id.uuidString)\",\"mode\":\"edit\",\"text\":\"Fix grammar\"}]"
        #expect(QuickPrompts(rawValue: stored).items
            == [QuickPrompt(id: id, text: "Fix grammar", modes: [.edit])])
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
        let blank = QuickPrompt(text: "  \n ", modes: [.ask])
        let many = (0..<10).map { QuickPrompt(text: "Prompt \($0)", modes: [.edit]) }
        let prompts = QuickPrompts(items: [blank] + many)

        #expect(prompts.visible.count == QuickPrompts.limit)
        #expect(prompts.visible.first?.text == "Prompt 0")
    }

    @Test("Each mode of the bar gets its own prompts and those in both, in order")
    func perMode() {
        let prompts = QuickPrompts(items: [
            QuickPrompt(text: "What does this mean?", modes: [.ask]),
            QuickPrompt(text: "Summarize", modes: [.ask, .edit]),
            QuickPrompt(text: "Fix grammar", modes: [.edit]),
        ])
        #expect(prompts.visible(in: .ask).map(\.text) == ["What does this mean?", "Summarize"])
        #expect(prompts.visible(in: .edit).map(\.text) == ["Summarize", "Fix grammar"])
    }

    @Test("Instructions are trimmed, and each mode maps to its intent")
    func instruction() {
        #expect(QuickPrompt(text: "  Fix grammar \n", modes: [.edit]).instruction == "Fix grammar")
        #expect(QuickPrompt.Mode.ask.intent == .ask)
        #expect(QuickPrompt.Mode.edit.intent == .auto)
    }
}
