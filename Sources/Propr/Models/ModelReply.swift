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
