import Foundation

/// Which gestures summon Propr. Each defaults to on, and is read at the moment the
/// gesture happens, so changing one in Settings applies without a relaunch.
enum TriggerPreferences {
    static let refineDoubleTapKey = "trigger.refineDoubleTap"
    static let fnLookupKey = "trigger.fnLookup"
    static let forceClickLookupKey = "trigger.forceClickLookup"

    static var refineDoubleTapEnabled: Bool { enabled(refineDoubleTapKey) }
    static var fnLookupEnabled: Bool { enabled(fnLookupKey) }
    static var forceClickLookupEnabled: Bool { enabled(forceClickLookupKey) }

    /// A missing value means the user never turned the trigger off.
    private static func enabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
