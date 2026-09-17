import Foundation
import Testing

@testable import Propr

/// Pins the pacing used when typing generated text into another app.
///
/// The delay is a compromise: too fast and the target app drops keystrokes, too slow
/// and a long reply takes a minute to appear. These tests fix both ends of that.
@MainActor
struct KeystrokePacingTests {

    private func delayMilliseconds(_ count: Int) -> Double {
        let delay = SourceAppKeyboard.keystrokeDelay(forCharacterCount: count)
        return Double(delay.nanoseconds) / 1_000_000
    }

    /// Roughly how long typing `count` characters would take, in seconds.
    private func runSeconds(_ count: Int) -> Double {
        delayMilliseconds(count) * Double(count) / 1000
    }

    @Test("Short replies keep the relaxed, readable pacing")
    func shortTextIsRelaxed() {
        #expect(delayMilliseconds(20) == 18)
        #expect(delayMilliseconds(100) == 18)
    }

    @Test("A long reply is compressed to stay near the budget")
    func longTextIsCompressed() {
        // The old flat 18ms put this at roughly 54 seconds.
        #expect(runSeconds(3_000) < 12)
        #expect(delayMilliseconds(3_000) < 18)
    }

    @Test("Pacing never drops below the floor where apps drop events")
    func neverBelowFloor() {
        for count in [5_000, 50_000, 1_000_000] {
            #expect(delayMilliseconds(count) >= 3)
        }
    }

    @Test("Pacing never exceeds the relaxed delay")
    func neverAboveRelaxed() {
        for count in [0, 1, 2, 10, 500, 100_000] {
            #expect(delayMilliseconds(count) <= 18)
        }
    }

    @Test("Delay decreases monotonically as the text gets longer")
    func monotonic() {
        let counts = [1, 10, 100, 250, 500, 1_000, 5_000]
        let delays = counts.map(delayMilliseconds)
        #expect(delays == delays.sorted(by: >))
    }

    @Test("Degenerate lengths do not produce a zero or negative delay")
    func degenerateCounts() {
        #expect(delayMilliseconds(0) > 0)
        #expect(delayMilliseconds(1) > 0)
        #expect(delayMilliseconds(-5) > 0)
    }
}
