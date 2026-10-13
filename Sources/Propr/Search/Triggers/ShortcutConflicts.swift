import Foundation

/// A macOS shortcut that fires on the same gesture as one of Propr's lookup
/// triggers, so both would happen at once.
struct ShortcutConflict: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Tapping Fn/Globe also changes input source, opens emoji or starts dictation.
        case fnKey(action: String)
        /// Force Click also opens the system Look Up popover.
        case forceClickLookUp
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .fnKey: "fn"
        case .forceClickLookUp: "forceClick"
        }
    }

    var title: String {
        switch kind {
        case .fnKey(let action): "Fn also opens \(action)"
        case .forceClickLookUp: "Force Click also opens Look Up"
        }
    }

    var fix: String {
        switch kind {
        case .fnKey: "In Keyboard settings, set “Press 🌐 key to” to Do Nothing."
        case .forceClickLookUp:
            "In Trackpad settings, set “Look up & data detectors” to Tap with Three Fingers, or turn it off."
        }
    }

    var settingsPaneURL: URL {
        switch kind {
        case .fnKey: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        case .forceClickLookUp: URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
        }
    }
}

/// Reads the two system settings that collide with Propr's lookup triggers.
///
/// The decision is pure, taking the raw preference values, so it can be tested
/// without touching the user's settings. Propr is not sandboxed, so it can read
/// these system preference domains directly.
enum ShortcutConflictDetector {
    /// - Parameters:
    ///   - fnUsageType: `AppleFnUsageType` from `com.apple.HIToolbox`. 0 is Do Nothing.
    ///     Nil means it was never changed, and the macOS default then is Show Emoji &
    ///     Symbols, so a missing value is a conflict too.
    ///   - forceClickEnabled: the global `com.apple.trackpad.forceClick` switch.
    ///   - threeFingerTapGesture: `TrackpadThreeFingerTapGesture`. 0 leaves Look Up
    ///     on Force Click; 2 moves it to a three-finger tap.
    static func conflicts(
        fnUsageType: Int?, forceClickEnabled: Bool, threeFingerTapGesture: Int
    ) -> [ShortcutConflict] {
        var found: [ShortcutConflict] = []

        switch fnUsageType ?? 2 {
        case 0: break
        case 1: found.append(.init(kind: .fnKey(action: "Change Input Source")))
        case 2: found.append(.init(kind: .fnKey(action: "Emoji & Symbols")))
        case 3: found.append(.init(kind: .fnKey(action: "Dictation")))
        default: found.append(.init(kind: .fnKey(action: "another system action")))
        }

        if forceClickEnabled && threeFingerTapGesture == 0 {
            found.append(.init(kind: .forceClickLookUp))
        }
        return found
    }

    /// The conflicts on this Mac right now.
    static func current() -> [ShortcutConflict] {
        let fnUsageType = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .object(forKey: "AppleFnUsageType") as? Int
        let forceClickEnabled = UserDefaults.standard.bool(forKey: "com.apple.trackpad.forceClick")
        let threeFingerTap =
            UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")?
            .integer(forKey: "TrackpadThreeFingerTapGesture") ?? 0

        return conflicts(
            fnUsageType: fnUsageType,
            forceClickEnabled: forceClickEnabled,
            threeFingerTapGesture: threeFingerTap)
    }
}
