import AppKit
@preconcurrency import ApplicationServices

/// Writes generated text into a focused text field through the Accessibility API.
///
/// This is the preferred path: unlike `SourceAppKeyboard` it does not synthesise
/// keystrokes or borrow the pasteboard, so it cannot disturb anything outside the
/// field being written to. It only works where the app exposes a settable
/// `kAXSelectedText`, which `FloatingBarController.strategy(for:role:appName:)` checks.
///
/// Text is written one streamed token at a time, so a failure part-way leaves partial
/// text rather than nothing.
@MainActor
struct AXTextWriter {
    let element: AXUIElement

    /// Clears the insertion point ready for generated text.
    ///
    /// - Parameter replacingWholeValue: select the field's entire contents first, so
    ///   the generated text replaces it rather than being appended.
    func prepareForReplacement(replacingWholeValue: Bool) throws {
        if replacingWholeValue {
            selectEntireValue()
        }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            "" as CFString
        )
        guard status == .success else {
            throw TextApplyError.cannotWriteAX
        }
    }

    /// Appends a streamed token.
    ///
    /// Written whole rather than character by character with an artificial delay.
    /// The model emits tokens every 20–50ms, so the stream already paces itself; the
    /// old per-character delay was slower than the model produced text, which meant
    /// the animation fell behind and the total time was dominated by our own sleeps
    /// rather than the request. A 500-character reply took about eleven seconds.
    func append(_ token: String) async throws {
        guard !token.isEmpty else { return }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            token as CFString
        )
        guard status == .success else {
            throw TextApplyError.cannotWriteAX
        }
    }

    /// Replaces the whole field with `text` in one write, used to undo an apply.
    func replaceAll(with text: String) {
        selectEntireValue()
        AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString)
    }

    /// Selects the field's current contents. Silent on failure: callers treat a
    /// missing selection as "append at the insertion point", which is the safer
    /// outcome than refusing to write at all.
    private func selectEntireValue() {
        var currentValue: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
                == .success,
            let text = currentValue as? String,
            !text.isEmpty
        else {
            return
        }

        var range = CFRange(location: 0, length: (text as NSString).length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return }

        AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    }
}
