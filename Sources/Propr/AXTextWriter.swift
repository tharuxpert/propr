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

    /// Selects exactly the text Propr wrote on the previous turn. Refuses to move the
    /// selection when the field no longer matches, so a follow-up cannot overwrite a
    /// user's intervening edit or text whose range shifted behind Propr's back.
    func selectPreviouslyAppliedText(_ expected: String, range: CFRange) throws {
        var valueRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
            let value = valueRef as? String
        else {
            throw TextApplyError.cannotWriteAX
        }

        let nsValue = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard range.location >= 0, range.length >= 0, NSMaxRange(nsRange) <= nsValue.length,
            nsValue.substring(with: nsRange) == expected
        else {
            throw TextApplyError.sourceChanged
        }

        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            throw TextApplyError.cannotWriteAX
        }
        let status = AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
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

    /// Everything needed to put a field back as it was: its whole value, and where
    /// the selection or caret sat.
    struct FieldState {
        let value: String
        let selectedRange: CFRange?
    }

    /// Reads the field's current value and selection, or nil if the value cannot be
    /// read — in which case there is no safe way to restore it.
    func currentState() -> FieldState? {
        var valueRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
            let value = valueRef as? String
        else {
            return nil
        }

        var selectedRange: CFRange?
        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(rangeRef, to: AXValue.self), .cfRange, &range) {
                selectedRange = range
            }
        }

        return FieldState(value: value, selectedRange: selectedRange)
    }

    /// Puts the field back exactly as it was: the whole value, then the selection, so
    /// the user is left where they were before summoning — e.g. with their original
    /// word selected again.
    func restore(_ state: FieldState) {
        selectEntireValue()
        AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, state.value as CFString)

        if var range = state.selectedRange, let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
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
