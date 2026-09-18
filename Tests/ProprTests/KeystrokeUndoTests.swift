import Testing

@testable import Propr

/// Which undo Propr uses for text it inserted without the Accessibility API.
///
/// ⌘Z does not work at a shell prompt, so terminals get Backspace — and because
/// terminals receive a bracketed paste, the whole answer is still on the prompt.
struct KeystrokeUndoTests {

    @Test("A terminal insertion is undone with exactly that many Backspaces", arguments: [
        "Warp", "Terminal", "iTerm2", "Ghostty",
    ])
    func terminalUsesBackspace(_ app: String) {
        let plan = KeystrokeUndo.plan(appName: app, insertedText: "git status", replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: 10))
    }

    /// The reported bug: a multi-line answer, and Undo only removed the last line.
    /// A bracketed paste keeps every line on the prompt, in every terminal.
    @Test("Every line of a multi-line answer is deleted, in every terminal", arguments: [
        "Warp", "Terminal", "iTerm2", "Ghostty",
    ])
    func multiLineDeletesEverything(_ app: String) {
        let answer = "git add .\ngit commit -m \"wip\""
        let plan = KeystrokeUndo.plan(appName: app, insertedText: answer, replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: answer.count))
    }

    @Test("Ordinary apps keep ⌘Z, which can also undo a replacement", arguments: [
        "Notes", "Slack", "Visual Studio Code",
    ])
    func ordinaryAppsUseUndoShortcut(_ app: String) {
        let plan = KeystrokeUndo.plan(appName: app, insertedText: "hello", replacedExisting: false)
        #expect(plan == .undoShortcut)
    }

    /// Backspace can only remove text; it cannot bring back what was replaced.
    @Test("Replaced text falls back to ⌘Z even in a terminal")
    func replacementInTerminal() {
        let plan = KeystrokeUndo.plan(appName: "Warp", insertedText: "new text", replacedExisting: true)
        #expect(plan == .undoShortcut)
    }

    @Test("Counts characters, not bytes, so non-ASCII text is not over-deleted")
    func nonASCII() {
        #expect(KeystrokeUndo.plan(appName: "Warp", insertedText: "café", replacedExisting: false)
            == .deleteTyped(characterCount: 4))
        #expect(KeystrokeUndo.plan(appName: "Warp", insertedText: "👋🏽 hi", replacedExisting: false)
            == .deleteTyped(characterCount: 4))
    }

    @Test("Nothing inserted means nothing to delete")
    func emptyText() {
        let plan = KeystrokeUndo.plan(appName: "Warp", insertedText: "", replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: 0))
    }

    /// A carriage return is Return to a shell, and Undo counts one character per line
    /// break — so pasted text must use a single "\n" for every break.
    @Test("Line endings are normalised to a single newline before pasting", arguments: [
        ("a\r\nb", "a\nb"),
        ("a\rb", "a\nb"),
        ("a\nb", "a\nb"),
        ("one\r\ntwo\rthree", "one\ntwo\nthree"),
    ])
    @MainActor
    func normalisesLineEndings(_ input: String, _ expected: String) {
        #expect(FloatingBarController.normalizingLineEndings(input) == expected)
    }
}
