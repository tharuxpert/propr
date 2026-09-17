import AppKit
import Testing

@testable import Propr

/// The summon hotkey is a double tap of Command *on its own*. Getting this wrong
/// either swallows ordinary shortcuts or makes the bar appear while the user is
/// pressing ⌘S.
struct HotkeyTests {

    @Test("Command alone counts")
    func commandAlone() {
        #expect(AppDelegate.isPureCommand([.command]))
    }

    @Test("Command with another modifier does not count", arguments: [
        NSEvent.ModifierFlags.shift,
        .option,
        .control,
        .function,
    ])
    func commandWithModifier(_ other: NSEvent.ModifierFlags) {
        #expect(AppDelegate.isPureCommand([.command, other]) == false)
    }

    @Test("Modifiers without Command do not count", arguments: [
        NSEvent.ModifierFlags.shift,
        .option,
        .control,
        .function,
        [],
    ])
    func withoutCommand(_ flags: NSEvent.ModifierFlags) {
        #expect(AppDelegate.isPureCommand(flags) == false)
    }

    /// Caps Lock and numeric-pad bits ride along on ordinary events and must not
    /// disqualify an otherwise-pure Command press.
    @Test("Incidental flags do not disqualify Command", arguments: [
        NSEvent.ModifierFlags.capsLock,
        .numericPad,
    ])
    func incidentalFlags(_ incidental: NSEvent.ModifierFlags) {
        #expect(AppDelegate.isPureCommand([.command, incidental]))
    }

    @Test("The double-tap window is a sane length")
    func doubleTapWindow() {
        #expect(AppDelegate.doubleCommandWindow > 0.2)
        #expect(AppDelegate.doubleCommandWindow < 1.0)
    }
}
