import AppKit

/// Recognizes one short, unmodified Fn/Globe press on release.
/// Both local and global monitors may report the same transition; the held
/// state makes repeated down/up deliveries harmless.
@MainActor
final class FnTapDetector {
    static let keyCode: UInt16 = 63
    static let maximumDuration: TimeInterval = 0.3

    private var pressedAt: TimeInterval?
    private var usedInChord = false

    func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags, at time: TimeInterval) -> Bool {
        let modifiers: NSEvent.ModifierFlags = [.function, .command, .control, .option, .shift]
        let relevantFlags = flags.intersection(modifiers)

        if keyCode != Self.keyCode {
            if pressedAt != nil, relevantFlags != [.function] {
                usedInChord = true
            }
            return false
        }

        if flags.contains(.function) {
            if pressedAt == nil {
                pressedAt = time
                usedInChord = relevantFlags != [.function]
            } else if relevantFlags != [.function] {
                usedInChord = true
            }
            return false
        }

        guard let start = pressedAt else { return false }
        pressedAt = nil
        defer { usedInChord = false }
        return !usedInChord
            && relevantFlags.isEmpty
            && time >= start
            && time - start <= Self.maximumDuration
    }

    func keyDown() {
        if pressedAt != nil { usedInChord = true }
    }

    func reset() {
        pressedAt = nil
        usedInChord = false
    }
}
