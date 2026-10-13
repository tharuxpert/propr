import Testing

@testable import Propr

/// Tapping Fn and Force Clicking can also fire macOS shortcuts. These pin down
/// which system setting values count as a clash with Propr's lookup triggers.
struct ShortcutConflictTests {
    private func kinds(
        fn: Int?, forceClick: Bool = false, threeFingerTap: Int = 0
    ) -> [ShortcutConflict.Kind] {
        ShortcutConflictDetector.conflicts(
            fnUsageType: fn, forceClickEnabled: forceClick, threeFingerTapGesture: threeFingerTap
        ).map(\.kind)
    }

    @Test("Fn set to Do Nothing is no conflict")
    func fnDoNothing() {
        #expect(kinds(fn: 0).isEmpty)
    }

    @Test("Every other Fn action is a conflict", arguments: [
        (1, "Change Input Source"),
        (2, "Emoji & Symbols"),
        (3, "Dictation"),
    ])
    func fnActions(_ value: Int, action: String) {
        #expect(kinds(fn: value) == [.fnKey(action: action)])
    }

    /// An untouched Mac has no AppleFnUsageType at all, and its default is Show
    /// Emoji & Symbols. Reading the missing value as 0 would hide that clash.
    @Test("A never-changed Fn key counts as the Emoji default")
    func fnUnset() {
        #expect(kinds(fn: nil) == [.fnKey(action: "Emoji & Symbols")])
    }

    @Test("Look Up on Force Click is a conflict")
    func forceClickLookUp() {
        #expect(kinds(fn: 0, forceClick: true, threeFingerTap: 0) == [.forceClickLookUp])
    }

    @Test("Look Up moved to three fingers, or Force Click off, is no conflict")
    func forceClickClear() {
        #expect(kinds(fn: 0, forceClick: true, threeFingerTap: 2).isEmpty)
        #expect(kinds(fn: 0, forceClick: false, threeFingerTap: 0).isEmpty)
    }
}
