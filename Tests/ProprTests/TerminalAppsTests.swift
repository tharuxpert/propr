import Testing

@testable import Propr

/// Terminals get different treatment from ordinary text fields: ⌘A there selects
/// the scrollback rather than the prompt, so it must never be used to capture context.
struct TerminalAppsTests {

    @Test("Known terminals are recognised, whatever the capitalisation", arguments: [
        "Warp", "Terminal", "iTerm2", "Ghostty", "WezTerm", "Alacritty", "kitty",
    ])
    func recognisesTerminals(_ name: String) {
        #expect(TerminalApps.isTerminal(appName: name))
    }

    @Test("Ordinary apps are not treated as terminals", arguments: [
        "Notes", "Mail", "TextEdit", "Safari", "Visual Studio Code", "Slack",
    ])
    func ordinaryApps(_ name: String) {
        #expect(TerminalApps.isTerminal(appName: name) == false)
    }

    /// The reported bug: summoning in Warp with nothing selected pressed ⌘A — which in
    /// Warp is "Select All Blocks" — and sent the whole command history to the model,
    /// which then became the message of a generated `git commit -m`.
    @Test("Select-all capture is never used in a terminal", arguments: [
        "Warp", "Terminal", "iTerm2", "Ghostty",
    ])
    func noSelectAllInTerminals(_ name: String) {
        #expect(TerminalApps.allowsSelectAllCapture(appName: name) == false)
    }

    @Test("Select-all capture is still used in ordinary apps", arguments: [
        "Notes", "Mail", "Slack",
    ])
    func selectAllElsewhere(_ name: String) {
        #expect(TerminalApps.allowsSelectAllCapture(appName: name))
    }

}
