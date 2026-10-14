import Foundation

/// How the refine bar behaves, as chosen in Settings.
enum RefinePreferences {
    /// The mode a freshly summoned bar opens in. Tab still switches it.
    enum StartMode: String, CaseIterable {
        case edit
        case ask

        var title: String {
            switch self {
            case .edit: "Edit"
            case .ask: "Ask"
            }
        }
    }

    static let customInstructionsKey = "refine.customInstructions"
    static let startModeKey = "refine.startMode"

    static var startMode: StartMode {
        startMode(stored: UserDefaults.standard.string(forKey: startModeKey))
    }

    /// Edit when unset, or when the stored value no longer names a mode.
    static func startMode(stored: String?) -> StartMode {
        stored.flatMap(StartMode.init(rawValue:)) ?? .edit
    }

    /// Long enough for a handful of preferences, short enough that it cannot crowd
    /// out the actual request or run up cost on every call.
    static let customInstructionsLimit = 1_000

    /// Standing preferences added to every refine and Ask request.
    static var customInstructions: String {
        String((UserDefaults.standard.string(forKey: customInstructionsKey) ?? "").prefix(customInstructionsLimit))
    }
}
