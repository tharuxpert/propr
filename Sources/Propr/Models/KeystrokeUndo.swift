import Foundation

/// How to reverse text that Propr typed into another app with synthesised keystrokes.
enum KeystrokeUndo: Equatable {
    /// Ask the app to undo its last edit with ⌘Z.
    case undoShortcut

    /// Press Backspace this many times, deleting exactly what Propr typed.
    case deleteTyped(characterCount: Int)

    /// Chooses the undo for one apply.
    ///
    /// Terminals get Backspace. A shell prompt is not a document: zsh and bash run their
    /// own line editors, and most terminals ignore ⌘Z or pass it through as input. And
    /// in a terminal Backspace is exact rather than approximate, because terminal
    /// applies are always pure insertion at the cursor — Propr never selects-all there.
    ///
    /// Anywhere text was *replaced*, Backspace cannot bring the old text back, so ⌘Z is
    /// the only option even in a terminal.
    static func plan(appName: String, typedText: String, replacedExisting: Bool) -> KeystrokeUndo {
        guard TerminalApps.isTerminal(appName: appName), !replacedExisting else {
            return .undoShortcut
        }
        let count =
            TerminalApps.keepsTypedNewlines(appName: appName)
            ? typedText.count
            : editableCharacterCount(of: typedText)
        return .deleteTyped(characterCount: count)
    }

    /// How many typed characters are still on the prompt, for a terminal whose shell
    /// runs each line as a newline is typed (see `TerminalApps.keepsTypedNewlines`).
    ///
    /// There, a typed newline behaves like Return: the line runs, nothing can undo that,
    /// and it is no longer on the prompt to delete. Only what follows the last newline
    /// is still there, so only that is counted — deleting further would just ring the
    /// bell at an empty prompt. Terminals that keep typed newlines count everything.
    ///
    /// Counts `Character`s, the unit Propr types in. A line editor may treat a
    /// combined character as several, in which case this deletes slightly too little
    /// and leaves a remnant — the safe direction, since deleting too much would eat
    /// text the user had typed before summoning.
    static func editableCharacterCount(of typedText: String) -> Int {
        let lastLine = typedText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last
        return lastLine?.count ?? 0
    }
}
