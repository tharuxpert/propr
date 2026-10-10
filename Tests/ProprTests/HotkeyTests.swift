import AppKit
import Testing

@testable import Propr

/// The summon hotkey is a double tap of Command *on its own*. Getting this wrong
/// either swallows ordinary shortcuts or makes the bar appear while the user is
/// pressing ⌘S or ⌘⇧2.
@MainActor
struct HotkeyTests {
    private static let leftCommand: UInt16 = 55
    private static let rightCommand: UInt16 = 54
    private static let shift: UInt16 = 56
    private static let option: UInt16 = 58

    @Test("The test host knows it is hosting tests, so it skips the ⌘⌘ listener")
    func testHostSkipsLaunchSetup() {
        #expect(AppDelegate.isHostingTests)
    }

    /// Presses and releases left Command, returning whether the release summoned.
    private func tap(_ detector: CommandDoubleTapDetector, at time: TimeInterval) -> Bool {
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command], at: time)
        return detector.flagsChanged(keyCode: Self.leftCommand, flags: [], at: time + 0.05)
    }

    @Test("Two quick Command taps summon")
    func doubleTap() {
        let detector = CommandDoubleTapDetector()
        #expect(tap(detector, at: 0) == false)
        #expect(tap(detector, at: 0.2))
    }

    @Test("Right Command counts like left")
    func rightCommand() {
        let detector = CommandDoubleTapDetector()
        _ = detector.flagsChanged(keyCode: Self.rightCommand, flags: [.command], at: 0)
        _ = detector.flagsChanged(keyCode: Self.rightCommand, flags: [], at: 0.05)
        _ = detector.flagsChanged(keyCode: Self.rightCommand, flags: [.command], at: 0.2)
        #expect(detector.flagsChanged(keyCode: Self.rightCommand, flags: [], at: 0.25))
    }

    @Test("A single tap does not summon")
    func singleTap() {
        #expect(tap(CommandDoubleTapDetector(), at: 0) == false)
    }

    @Test("Taps too far apart do not summon")
    func slowTaps() {
        let detector = CommandDoubleTapDetector()
        _ = tap(detector, at: 0)
        #expect(tap(detector, at: 1.0) == false)
    }

    @Test("A long hold is not a tap")
    func longHold() {
        let detector = CommandDoubleTapDetector()
        _ = tap(detector, at: 0)
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command], at: 0.1)
        #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: [], at: 0.8) == false)
    }

    /// The reported bug: releasing Shift while Command is still held reports flags of
    /// exactly [.command], which the old check counted as a second Command press.
    @Test("⌘⇧2 does not summon")
    func commandShiftShortcut() {
        let detector = CommandDoubleTapDetector()
        #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command], at: 0) == false)
        #expect(detector.flagsChanged(keyCode: Self.shift, flags: [.command, .shift], at: 0.05) == false)
        detector.interrupt() // the "2" key
        #expect(detector.flagsChanged(keyCode: Self.shift, flags: [.command], at: 0.15) == false)
        #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: [], at: 0.2) == false)
        #expect(tap(detector, at: 0.3) == false)
    }

    @Test("Shift pressed before Command does not count", arguments: [
        NSEvent.ModifierFlags.shift,
        .option,
        .control,
        .function,
    ])
    func modifierHeldFirst(_ other: NSEvent.ModifierFlags) {
        let detector = CommandDoubleTapDetector()
        for start in [0.0, 0.2] {
            _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command, other], at: start)
            #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: other, at: start + 0.05) == false)
        }
    }

    @Test("⌘C then ⌘V does not summon")
    func twoShortcuts() {
        let detector = CommandDoubleTapDetector()
        for start in [0.0, 0.2] {
            _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command], at: start)
            detector.interrupt()
            #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: [], at: start + 0.1) == false)
        }
    }

    @Test("A key between two clean taps cancels the pair")
    func keyBetweenTaps() {
        let detector = CommandDoubleTapDetector()
        _ = tap(detector, at: 0)
        detector.interrupt()
        #expect(tap(detector, at: 0.2) == false)
    }

    @Test("Another modifier between two taps cancels the pair")
    func modifierBetweenTaps() {
        let detector = CommandDoubleTapDetector()
        _ = tap(detector, at: 0)
        _ = detector.flagsChanged(keyCode: Self.option, flags: [.option], at: 0.1)
        _ = detector.flagsChanged(keyCode: Self.option, flags: [], at: 0.15)
        #expect(tap(detector, at: 0.2) == false)
    }

    @Test("Pressing both Command keys is not a tap")
    func bothCommandKeys() {
        let detector = CommandDoubleTapDetector()
        _ = tap(detector, at: 0)
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command], at: 0.2)
        _ = detector.flagsChanged(keyCode: Self.rightCommand, flags: [.command], at: 0.22)
        _ = detector.flagsChanged(keyCode: Self.rightCommand, flags: [.command], at: 0.25)
        #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: [], at: 0.28) == false)
    }

    /// Caps Lock and numeric-pad bits ride along on ordinary events and must not
    /// disqualify an otherwise-pure Command tap.
    @Test("Incidental flags do not disqualify Command", arguments: [
        NSEvent.ModifierFlags.capsLock,
        .numericPad,
    ])
    func incidentalFlags(_ incidental: NSEvent.ModifierFlags) {
        let detector = CommandDoubleTapDetector()
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command, incidental], at: 0)
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: incidental, at: 0.05)
        _ = detector.flagsChanged(keyCode: Self.leftCommand, flags: [.command, incidental], at: 0.2)
        #expect(detector.flagsChanged(keyCode: Self.leftCommand, flags: incidental, at: 0.25))
    }
}
