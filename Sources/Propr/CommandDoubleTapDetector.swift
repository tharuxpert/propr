import AppKit

/// Recognizes a double tap of Command on its own.
///
/// A tap is a Command key going down and back up with nothing else in between:
/// no other modifier, no key, no click. Counting raw "flags are Command only"
/// events is not enough — releasing Shift out of ⌘⇧2 reports exactly that, and
/// ⌘C followed by ⌘V never changes the flags beyond Command at all.
@MainActor
final class CommandDoubleTapDetector {
    /// Left and right Command.
    static let keyCodes: Set<UInt16> = [55, 54]
    /// Longest a single press may be held and still count as a tap.
    static let maximumTapDuration: TimeInterval = 0.35
    /// Longest gap between the two taps' releases.
    static let doubleTapWindow: TimeInterval = 0.45

    private static let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]

    private var pressedAt: TimeInterval?
    private var usedInChord = false
    private var lastTapAt: TimeInterval?

    /// Returns true when this event completes a double tap.
    func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, at time: TimeInterval) -> Bool {
        let relevantFlags = flags.intersection(Self.modifiers)

        guard Self.keyCodes.contains(keyCode) else {
            interrupt()
            return false
        }

        if relevantFlags.contains(.command) {
            if pressedAt == nil {
                pressedAt = time
                usedInChord = relevantFlags != [.command]
            } else {
                // The other Command key joined, or one of two was released.
                usedInChord = true
            }
            return false
        }

        guard let start = pressedAt else { return false }
        pressedAt = nil
        defer { usedInChord = false }

        guard !usedInChord,
            relevantFlags.isEmpty,
            time >= start,
            time - start <= Self.maximumTapDuration
        else {
            lastTapAt = nil
            return false
        }

        if let last = lastTapAt, time - last <= Self.doubleTapWindow {
            lastTapAt = nil
            return true
        }
        lastTapAt = time
        return false
    }

    /// Any key press or click while Command is held, or between taps, breaks the sequence.
    func interrupt() {
        if pressedAt != nil { usedInChord = true }
        lastTapAt = nil
    }

    func reset() {
        pressedAt = nil
        usedInChord = false
        lastTapAt = nil
    }
}
