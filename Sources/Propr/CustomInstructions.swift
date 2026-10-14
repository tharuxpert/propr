import Foundation

/// The user's standing preferences, shared by the refine bar and Quick Lookup:
/// where they are stored, how long they may be, and how they are framed when added
/// to a system prompt.
///
/// Both surfaces inject them identically, so a preference means the same thing
/// wherever it is applied, and the two prompts cannot drift apart.
enum CustomInstructions {
    /// Long enough for a handful of preferences, short enough that it cannot crowd
    /// out the actual request or run up cost on every call.
    static let limit = 1_000

    static let refineKey = "refine.customInstructions"
    static let lookupKey = "lookup.customInstructions"

    /// The saved text, capped to `limit`. Empty when none are set.
    static func stored(under key: String) -> String {
        String((UserDefaults.standard.string(forKey: key) ?? "").prefix(limit))
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Delimited so the preferences read as the user's standing wishes, and ranked
    /// below the instruction so a one-off request can still override them.
    static func instruction(_ preferences: String) -> String {
        """
        The user's standing preferences are inside <user_preferences>. Follow them \
        unless the instruction asks for something different.
        <user_preferences>
        \(preferences)
        </user_preferences>
        """
    }

    /// `prompt` with the preferences appended, or unchanged when there are none.
    static func appended(_ preferences: String, to prompt: String) -> String {
        let preferences = trimmed(preferences)
        guard !preferences.isEmpty else { return prompt }
        return prompt + "\n\n" + instruction(preferences)
    }
}
