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

    static let customInstructionsKey = CustomInstructions.refineKey
    static let startModeKey = "refine.startMode"

    static var startMode: StartMode {
        startMode(stored: UserDefaults.standard.string(forKey: startModeKey))
    }

    /// Edit when unset, or when the stored value no longer names a mode.
    static func startMode(stored: String?) -> StartMode {
        stored.flatMap(StartMode.init(rawValue:)) ?? .edit
    }

    static let customInstructionsLimit = CustomInstructions.limit

    /// Standing preferences added to every refine and Ask request.
    static var customInstructions: String {
        CustomInstructions.stored(under: customInstructionsKey)
    }
}
