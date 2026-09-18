import Foundation

/// How to reverse text that Propr inserted into another app without the Accessibility
/// API — pasted into a terminal, or typed as keystrokes elsewhere.
enum KeystrokeUndo: Equatable {
    /// Ask the app to undo its last edit with ⌘Z.
    case undoShortcut

    /// Press Backspace this many times, deleting exactly what Propr inserted.
    case deleteTyped(characterCount: Int)

    /// Chooses the undo for one apply.
    ///
    /// Terminals get Backspace. A shell prompt is not a document: zsh and bash run their
    /// own line editors, and most terminals ignore ⌘Z or pass it through as input.
    ///
    /// It is exact there, not approximate. Terminals receive the answer as a bracketed
    /// paste, which lands in the command buffer whole — newlines included — and runs
    /// nothing, so every character Propr inserted is still on the prompt to delete.
    /// And terminal applies only ever insert at the cursor: Propr never selects-all in
    /// a terminal, so there is no replaced text that Backspace would fail to restore.
    ///
    /// Counts `Character`s. A line editor may treat a combined character as several,
    /// in which case this deletes slightly too little and leaves a remnant — the safe
    /// direction, since deleting too much would eat text the user typed before
    /// summoning.
    ///
    /// Anywhere text was *replaced*, Backspace cannot bring the old text back, so ⌘Z
    /// is the only option.
    static func plan(appName: String, insertedText: String, replacedExisting: Bool) -> KeystrokeUndo {
        guard TerminalApps.isTerminal(appName: appName), !replacedExisting else {
            return .undoShortcut
        }
        return .deleteTyped(characterCount: insertedText.count)
    }
}
