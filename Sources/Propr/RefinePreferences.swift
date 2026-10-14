import Foundation

/// How the refine bar behaves, as chosen in Settings.
enum RefinePreferences {
    static let customInstructionsKey = "refine.customInstructions"

    /// Long enough for a handful of preferences, short enough that it cannot crowd
    /// out the actual request or run up cost on every call.
    static let customInstructionsLimit = 1_000

    /// Standing preferences added to every refine and Ask request.
    static var customInstructions: String {
        String((UserDefaults.standard.string(forKey: customInstructionsKey) ?? "").prefix(customInstructionsLimit))
    }
}
