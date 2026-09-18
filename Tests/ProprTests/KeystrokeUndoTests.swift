import Testing

@testable import Propr

/// Which undo Propr uses for text it typed with synthesised keystrokes.
///
/// ⌘Z does not work at a shell prompt, so terminals get Backspace — but only when
/// that is exact, never when it would delete text the user typed themselves.
struct KeystrokeUndoTests {

    @Test("A terminal insertion is undone with exactly that many Backspaces", arguments: [
        "Warp", "Terminal", "iTerm2", "Ghostty",
    ])
    func terminalUsesBackspace(_ app: String) {
        let plan = KeystrokeUndo.plan(appName: app, typedText: "git status", replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: 10))
    }

    @Test("Ordinary apps keep ⌘Z, which can also undo a replacement", arguments: [
        "Notes", "Slack", "Visual Studio Code",
    ])
    func ordinaryAppsUseUndoShortcut(_ app: String) {
        let plan = KeystrokeUndo.plan(appName: app, typedText: "hello", replacedExisting: false)
        #expect(plan == .undoShortcut)
    }

    /// Backspace can only remove text; it cannot bring back what was replaced.
    @Test("Replaced text falls back to ⌘Z even in a terminal")
    func replacementInTerminal() {
        let plan = KeystrokeUndo.plan(appName: "Warp", typedText: "new text", replacedExisting: true)
        #expect(plan == .undoShortcut)
    }

    /// A newline typed into a terminal presses Return and runs the line. That line is
    /// no longer on the prompt, so only what came after the last newline is deleted.
    @Test("Only text after the last newline is still on the prompt", arguments: [
        ("ls -la\necho hi", 7),
        ("one\ntwo\nthree", 5),
        ("ends with newline\n", 0),
        ("windows\r\nline", 4),
    ])
    func multiLine(_ typed: String, _ remaining: Int) {
        #expect(KeystrokeUndo.editableCharacterCount(of: typed) == remaining)
    }

    /// The reported bug: in Warp's prompt a typed newline adds a line instead of
    /// running the command, so every line stays — and Undo only removed the last one.
    @Test("In Warp every typed line is deleted, not just the last")
    func warpKeepsAllLines() {
        let typed = "git add .\ngit commit -m \"wip\""
        let plan = KeystrokeUndo.plan(appName: "Warp", typedText: typed, replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: typed.count))
    }

    /// zsh and bash run a line when a newline is typed, so only the last is left.
    @Test("Where the shell runs each line, only the last line is deleted", arguments: [
        "Terminal", "iTerm2", "Ghostty",
    ])
    func shellRunsLines(_ app: String) {
        let plan = KeystrokeUndo.plan(
            appName: app, typedText: "git add .\ngit status", replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: 10))
    }

    @Test("Counts characters, not bytes, so non-ASCII text is not over-deleted")
    func nonASCII() {
        #expect(KeystrokeUndo.editableCharacterCount(of: "café") == 4)
        #expect(KeystrokeUndo.editableCharacterCount(of: "👋🏽 hi") == 4)
    }

    @Test("Nothing typed means nothing to delete")
    func emptyText() {
        let plan = KeystrokeUndo.plan(appName: "Warp", typedText: "", replacedExisting: false)
        #expect(plan == .deleteTyped(characterCount: 0))
    }
}
