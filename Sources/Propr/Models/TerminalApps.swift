import Foundation

/// Knowledge about terminal emulators, which break the assumptions Propr makes about
/// ordinary text fields.
///
/// Previously duplicated verbatim in the focus detector and the floating bar
/// controller; one list now, so a terminal added to one cannot be missed by the other.
enum TerminalApps {
    /// Substrings of the app names treated as terminals.
    private static let nameFragments = [
        "warp", "terminal", "iterm", "ghostty", "wezterm", "alacritty", "kitty",
    ]

    static func isTerminal(appName: String) -> Bool {
        let lowered = appName.lowercased()
        return nameFragments.contains { lowered.contains($0) }
    }

    /// Whether ⌘A + ⌘C can be used to capture "what the user has typed" as context.
    ///
    /// Not in a terminal. There, ⌘A does not select the prompt you are typing in:
    /// Terminal.app, iTerm and Ghostty select the whole scrollback, and in Warp ⌘A is
    /// "Select All Blocks" — every command and its output. Capturing that sent a
    /// terminal's history to the model as the text to rewrite, which then came back
    /// as the body of a `git commit -m`. With no selection in a terminal there is
    /// simply no context, and the user can ask for a command to be generated.
    static func allowsSelectAllCapture(appName: String) -> Bool {
        !isTerminal(appName: appName)
    }
}
