import Foundation

/// What the model sent back: text to put into the user's document, or a message
/// explaining that it could not do what was asked.
///
/// Without this distinction, a reply like "I'm sorry, I need more context" was
/// written straight into the user's editor as if it were the answer. The model is
/// told (see `ChatCompletionRequest`) to start such replies with `cannotMarker`, and
/// those are shown in the bar instead. Guessing from wording ("starts with I'm
/// sorry…") would be wrong: the user may well have asked for an apology.
enum ModelReply: Equatable {
    case text(String)
    case cannot(reason: String)

    /// ASCII, so models reproduce it exactly rather than paraphrasing it.
    static let cannotMarker = "PROPR_CANNOT:"

    static let defaultReason = "The model couldn't complete this request."

    /// Classifies a complete reply.
    static func parse(_ reply: String) -> ModelReply {
        let lead = leadingSkipped(reply)
        guard lead.lowercased().hasPrefix(cannotMarker.lowercased()) else {
            return .text(reply)
        }
        return .cannot(reason: reason(afterMarkerIn: lead))
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
/// be the "cannot" marker — so a refusal is never half-written into the user's
/// document before it is recognised.
///
/// Holds at most the length of the marker, and usually a single character: most
/// replies stop matching the marker on their first letter.
struct StreamingReplyFilter {
    private enum State {
        case undecided
        case passing
        case cannot
    }

    private var state = State.undecided
    private var held = ""

    /// Takes the next chunk from the model; returns the text that is safe to write now.
    mutating func receive(_ chunk: String) -> String {
        switch state {
        case .passing:
            return chunk

        case .cannot:
            held += chunk
            return ""

        case .undecided:
            held += chunk
            let lead = ModelReply.leadingSkipped(held).lowercased()
            let marker = ModelReply.cannotMarker.lowercased()

            if lead.hasPrefix(marker) {
                state = .cannot
                return ""
            }
            if marker.hasPrefix(lead) {
                // Still could be the marker (or nothing but leading whitespace yet).
                return ""
            }

            state = .passing
            defer { held = "" }
            return held
        }
    }

    /// Call once the stream has ended. `.cannot` means nothing was written and the
    /// reason belongs in the bar; `.text` carries anything still held back, to write.
    mutating func finish() -> ModelReply {
        defer { held = "" }
        switch state {
        case .cannot:
            return .cannot(reason: ModelReply.reason(afterMarkerIn: ModelReply.leadingSkipped(held)))
        case .undecided:
            // A reply short enough to be ambiguous the whole way through is still text.
            return .text(held)
        case .passing:
            return .text("")
        }
    }
}
