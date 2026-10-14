import Foundation

/// How Quick Lookup behaves, as chosen in Settings.
enum LookupPreferences {
    static let customInstructionsKey = CustomInstructions.lookupKey

    /// Standing preferences added to every Quick Lookup answer, separate from the
    /// bar's so the two surfaces can be tuned differently.
    static var customInstructions: String {
        CustomInstructions.stored(under: customInstructionsKey)
    }
}
