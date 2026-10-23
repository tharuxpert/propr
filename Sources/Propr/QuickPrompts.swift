import Foundation

/// One saved instruction the bar offers as a pill, sent with a single click.
struct QuickPrompt: Codable, Hashable, Identifiable, Sendable {
    /// A mode of the bar: answer in the bar, or edit the captured text. A prompt
    /// shows in the modes it is offered in and is sent in whichever is current,
    /// so "What does this mean?" never rewrites the text unless it was put in Edit.
    enum Mode: String, Codable, CaseIterable, Comparable, Sendable {
        case ask
        case edit

        var title: String {
            switch self {
            case .ask: "Ask"
            case .edit: "Edit"
            }
        }

        var intent: RefineIntent {
            switch self {
            case .ask: .ask
            case .edit: .auto
            }
        }

        static func < (lhs: Mode, rhs: Mode) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    var id = UUID()
    var text: String
    /// Never empty: Settings will not switch off a prompt's last mode.
    var modes: Set<Mode>

    init(id: UUID = UUID(), text: String, modes: Set<Mode>) {
        self.id = id
        self.text = text
        self.modes = modes
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, modes
        /// Before a prompt could be in both modes it stored just one.
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        if let modes = try container.decodeIfPresent(Set<Mode>.self, forKey: .modes), !modes.isEmpty {
            self.modes = modes
        } else {
            modes = [try container.decode(Mode.self, forKey: .mode)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        // Sorted so the stored text is stable.
        try container.encode(modes.sorted(), forKey: .modes)
    }

    /// The text as sent, or nil when it is blank and the pill should not show.
    var instruction: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The user's quick prompts, in the order the bar shows them.
///
/// Stored as JSON text so `@AppStorage` can hold it directly: Settings edits the
/// list and an open bar picks the change up without being summoned again.
struct QuickPrompts: RawRepresentable, Equatable, Sendable {
    static let key = "refine.quickPrompts"

    /// One row of pills fits under the bar; more than this would wrap or scroll.
    static let limit = 6
    /// Long enough for a real instruction, short enough to stay a pill.
    static let textLimit = 60

    static let defaults = QuickPrompts(items: [
        QuickPrompt(text: "What does this mean?", modes: [.ask]),
        QuickPrompt(text: "Explain in simple words", modes: [.ask]),
        QuickPrompt(text: "Make it shorter", modes: [.edit]),
        QuickPrompt(text: "Fix grammar", modes: [.edit]),
    ])

    var items: [QuickPrompt]

    init(items: [QuickPrompt]) {
        self.items = items
    }

    /// Falls back to the defaults when the stored text is not a list this version
    /// can read, so a bad value never leaves the bar without its pills.
    init(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
            let items = try? JSONDecoder().decode([QuickPrompt].self, from: data)
        else {
            self = Self.defaults
            return
        }
        self.items = items
    }

    /// Compares the prompts themselves. The `RawRepresentable` default would compare
    /// the JSON text instead.
    static func == (lhs: QuickPrompts, rhs: QuickPrompts) -> Bool {
        lhs.items == rhs.items
    }

    var rawValue: String {
        // Sorted keys keep the stored text stable, so writing back an unchanged list
        // is not seen as a change.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(items),
            let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    /// What the bar shows: blank prompts dropped, capped to `limit`.
    var visible: [QuickPrompt] {
        Array(items.filter { $0.instruction != nil }.prefix(Self.limit))
    }

    /// The pills for one mode of the bar, in order.
    func visible(in mode: QuickPrompt.Mode) -> [QuickPrompt] {
        visible.filter { $0.modes.contains(mode) }
    }

    var canAdd: Bool { items.count < Self.limit }

    static var stored: QuickPrompts {
        UserDefaults.standard.string(forKey: key).map(QuickPrompts.init(rawValue:)) ?? defaults
    }
}
