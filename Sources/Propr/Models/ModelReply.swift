import Foundation

/// What the model sent back: text to put into the user's document, a message
/// explaining that it could not do what was asked, or an answer to a question.
///
/// Without this distinction, a reply like "I'm sorry, I need more context" was
/// written straight into the user's editor as if it were the answer. The model is
/// told (see `ChatCompletionRequest`) to start such replies with a marker, and those
/// are shown in the bar instead. Guessing from wording ("starts with I'm sorry…",
/// "ends with ?") would be wrong: the user may well have asked for an apology, and
/// "can you make this shorter?" is an edit.
enum ModelReply: Equatable {
    case text(String)
    case cannot(reason: String)
    /// The user asked about the text rather than for a change to it.
    case answer(String)

    /// ASCII, so models reproduce it exactly rather than paraphrasing it.
    static let cannotMarker = "PROPR_CANNOT:"
    static let answerMarker = "PROPR_ANSWER:"

    static let defaultReason = "The model couldn't complete this request."

    /// Classifies a complete reply.
    ///
    /// With `acceptsAnswers` false — the user asked for an edit — an answer marker is
    /// dropped and what follows is the text. The model can still emit one, copying
    /// the marked answers in the history, and routing that to the bar again would
    /// make "Edit instead" do nothing.
    static func parse(_ reply: String, acceptsAnswers: Bool = true) -> ModelReply {
        let lead = leadingSkipped(reply)
        if hasMarker(cannotMarker, lead) {
            return .cannot(reason: reason(afterMarkerIn: lead))
        }
        if hasMarker(answerMarker, lead) {
            let body = answerBody(afterMarkerIn: lead)
            return acceptsAnswers ? .answer(body) : .text(body)
        }
        return .text(reply)
    }

    static func hasMarker(_ marker: String, _ lead: Substring) -> Bool {
        lead.lowercased().hasPrefix(marker.lowercased())
    }

    /// The answer after its marker. Only whitespace is trimmed: unlike a one-line
    /// reason, an answer may legitimately open or close with a quote or backtick.
    static func answerBody(afterMarkerIn lead: Substring) -> String {
        lead.dropFirst(answerMarker.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters a model may put before the marker without meaning anything by it:
    /// whitespace, and quotes or backticks when it "helpfully" formats its reply.
    static func leadingSkipped(_ text: String) -> Substring {
        text.drop { $0.isWhitespace || $0 == "`" || $0 == "\"" || $0 == "'" }
    }

    static func reason(afterMarkerIn lead: Substring) -> String {
        let reason = lead.dropFirst(cannotMarker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "`\"'")))
        return reason.isEmpty ? defaultReason : reason
    }
}

/// Text returned by the model after removing the optional caret-placement marker.
/// The offset uses UTF-16 because that is the coordinate system macOS Accessibility
/// text ranges use.
struct CursorMarkedText: Equatable {
    static let marker = "<PROPR_CURSOR>"

    let text: String
    let cursorUTF16Offset: Int?

    static func parse(_ reply: String) -> CursorMarkedText {
        var remaining = reply[...]
        var text = ""
        var cursorUTF16Offset: Int?

        while let range = remaining.range(of: marker) {
            let prefix = String(remaining[..<range.lowerBound])
            text += prefix
            if cursorUTF16Offset == nil {
                cursorUTF16Offset = text.utf16.count
            }
            remaining = remaining[range.upperBound...]
        }

        text += String(remaining)
        return CursorMarkedText(
            text: text,
            cursorUTF16Offset: cursorUTF16Offset ?? inferredEmptySlotOffset(in: text)
        )
    }

    /// Models do not always reproduce control markers reliably. An empty quoted
    /// value is still an unambiguous fill-in slot, so keep cursor placement useful
    /// for commands and templates even when the marker was omitted.
    private static func inferredEmptySlotOffset(in text: String) -> Int? {
        let pairs = ["''", "\"\""]
        let candidates = pairs.compactMap { pair -> String.Index? in
            text.range(of: pair)?.lowerBound
        }
        guard let openingQuote = candidates.min() else { return nil }
        let caret = text.index(after: openingQuote)
        return text[..<caret].utf16.count
    }

    /// Number of user-visible cursor steps from the requested caret to the end.
    /// Keyboard fallback targets use this after inserting the complete result.
    var trailingCharacterCount: Int {
        guard let cursorUTF16Offset else { return 0 }
        let utf16 = text.utf16
        guard
            let utf16Index = utf16.index(
                utf16.startIndex,
                offsetBy: cursorUTF16Offset,
                limitedBy: utf16.endIndex
            ),
            let index = String.Index(utf16Index, within: text)
        else {
            return 0
        }
        return text[index...].count
    }
}

/// Removes a cursor marker from a streamed answer without ever writing a partial
/// marker into the source app. At most `marker.count - 1` characters are held.
struct StreamingCursorMarkerFilter {
    private var held = ""
    private var emittedUTF16Count = 0
    private(set) var cursorUTF16Offset: Int?

    mutating func receive(_ chunk: String) -> String {
        held += chunk
        var output = ""

        while let range = held.range(of: CursorMarkedText.marker) {
            let prefix = String(held[..<range.lowerBound])
            output += prefix
            emittedUTF16Count += prefix.utf16.count
            if cursorUTF16Offset == nil {
                cursorUTF16Offset = emittedUTF16Count
            }
            held = String(held[range.upperBound...])
        }

        let heldSuffixCount = possibleMarkerPrefixSuffixLength(in: held)
        let safeEnd = held.index(held.endIndex, offsetBy: -heldSuffixCount)
        let safe = String(held[..<safeEnd])
        output += safe
        emittedUTF16Count += safe.utf16.count
        held = String(held[safeEnd...])
        return output
    }

    mutating func finish() -> String {
        defer { held = "" }
        emittedUTF16Count += held.utf16.count
        return held
    }

    private func possibleMarkerPrefixSuffixLength(in text: String) -> Int {
        let marker = CursorMarkedText.marker
        let maximum = min(text.count, marker.count - 1)
        guard maximum > 0 else { return 0 }

        for length in stride(from: maximum, through: 1, by: -1) {
            if marker.hasPrefix(text.suffix(length)) {
                return length
            }
        }
        return 0
    }
}

/// Streams a reply through, holding back output only while it could still turn out to
/// be a marker — so a refusal or an answer is never half-written into the user's
/// document before it is recognised.
///
/// Holds at most the length of a marker, and usually a single character: most
/// replies stop matching both markers on their first letter.
struct StreamingReplyFilter {
    private enum State {
        case undecided
        case passing
        case cannot
        case answer
        /// An answer marker on an edit request: dropped, with the text after it
        /// written as usual. See `ModelReply.parse(_:acceptsAnswers:)`.
        case strippingMarker
    }

    private static let markers: [(marker: String, state: State)] = [
        (ModelReply.cannotMarker.lowercased(), .cannot),
        (ModelReply.answerMarker.lowercased(), .answer),
    ]

    private let acceptsAnswers: Bool
    private var state = State.undecided
    private var held = ""

    init(acceptsAnswers: Bool = true) {
        self.acceptsAnswers = acceptsAnswers
    }

    /// The answer received so far, once the reply is known to be one, so the bar
    /// can show it as it streams in.
    var partialAnswer: String? {
        guard state == .answer else { return nil }
        return ModelReply.answerBody(afterMarkerIn: ModelReply.leadingSkipped(held))
    }

    /// Takes the next chunk from the model; returns the text that is safe to write now.
    mutating func receive(_ chunk: String) -> String {
        switch state {
        case .passing:
            return chunk

        case .cannot, .answer:
            held += chunk
            return ""

        case .strippingMarker:
            held += chunk
            return releaseTextAfterMarker()

        case .undecided:
            held += chunk
            let lead = ModelReply.leadingSkipped(held).lowercased()

            if let match = Self.markers.first(where: { lead.hasPrefix($0.marker) }) {
                if match.state == .answer && !acceptsAnswers {
                    state = .strippingMarker
                    return releaseTextAfterMarker()
                }
                state = match.state
                return ""
            }
            if Self.markers.contains(where: { $0.marker.hasPrefix(lead) }) {
                // Still could be a marker (or nothing but leading whitespace yet).
                return ""
            }

            state = .passing
            defer { held = "" }
            return held
        }
    }

    /// Call once the stream has ended. `.cannot` and `.answer` mean nothing was
    /// written and the reply belongs in the bar; `.text` carries anything still held
    /// back, to write.
    mutating func finish() -> ModelReply {
        defer { held = "" }
        let lead = ModelReply.leadingSkipped(held)
        switch state {
        case .cannot:
            return .cannot(reason: ModelReply.reason(afterMarkerIn: lead))
        case .answer:
            return .answer(ModelReply.answerBody(afterMarkerIn: lead))
        case .undecided:
            // A reply short enough to be ambiguous the whole way through is still text.
            return .text(held)
        case .passing, .strippingMarker:
            return .text("")
        }
    }

    /// Holds a stripped marker's trailing whitespace until real text follows, so the
    /// edit does not open with the space that separated it from the marker.
    private mutating func releaseTextAfterMarker() -> String {
        let body = ModelReply.leadingSkipped(held)
            .dropFirst(ModelReply.answerMarker.count)
            .drop(while: \.isWhitespace)
        guard !body.isEmpty else { return "" }
        state = .passing
        held = ""
        return String(body)
    }
}
