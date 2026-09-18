import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Foundation

/// Lightweight snapshot of a focused text field.
/// Does not hold the live AXUIElement (the controller captures that separately).
struct FieldSnapshot: Equatable {
    let appName: String
    let pid: pid_t
    let fullText: String
    let selectedText: String?
    let role: String?

    var characterCount: Int { fullText.count }
    var contextText: String { selectedText?.isEmpty == false ? selectedText! : fullText }
}

/// Reads the focused text field through the Accessibility API, at the moment it is
/// asked.
///
/// Stateless on purpose. It used to keep the last snapshot in a published cache,
/// refreshed on an 80ms debounce and cleared on a 250ms timer — machinery left over
/// from when the bar appeared automatically on focus changes. Summoning read that
/// cache 100ms after asking for a refresh, so it could show the *previous* summon's
/// context: sometimes, by losing a 20ms race; and always when the new field held
/// little or no text, because then the cache was not replaced, only scheduled to be
/// cleared 250ms later. Reading on demand leaves nothing to go stale.
@MainActor
struct FocusedFieldDetector {
    /// The focused element's contents right now, or nil when nothing is focused or
    /// the focus is inside Propr itself.
    func snapshotOfFocusedElement() -> FieldSnapshot? {
        var focusedRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                &focusedRef) == .success,
            let focusedRef,
            let element = axElement(from: focusedRef)
        else {
            return nil
        }
        return snapshot(of: element)
    }

    private func snapshot(of element: AXUIElement) -> FieldSnapshot? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0, pid != getpid() else { return nil }

        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown App"

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // Read the value only for actual editable text controls. Container roles such
        // as AXWebArea/AXGroup/AXWindow can expose huge app context or terminal
        // history, which must not be treated as the user's input field. Some terminals
        // (notably Warp) also expose their transcript as an editable value, so
        // suspiciously large or terminal values are dropped below.
        var valueRef: AnyObject?
        if isEditableTextRole(role) {
            _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        }
        let rawFullText = (valueRef as? String) ?? ""

        let fullText =
            shouldTrustAXValue(rawFullText, appName: appName, role: role) ? rawFullText : ""

        return FieldSnapshot(
            appName: appName,
            pid: pid,
            fullText: fullText,
            selectedText: selectedText(of: element, within: rawFullText),
            role: role
        )
    }

    /// The selected text, read directly when the element offers it, otherwise cut out
    /// of the value using the selected range.
    private func selectedText(of element: AXUIElement, within fullText: String) -> String? {
        var rangeRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let axRange = axValue(from: rangeRef),
            AXValueGetType(axRange) == .cfRange
        else {
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &cfRange) else { return nil }

        var selectedRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
            == .success,
            let selected = selectedRef as? String, !selected.isEmpty
        {
            return selected
        }

        let range = NSRange(location: cfRange.location, length: cfRange.length)
        let nsText = fullText as NSString
        guard range.length > 0, NSMaxRange(range) <= nsText.length else { return nil }
        return nsText.substring(with: range)
    }

    private func isEditableTextRole(_ role: String?) -> Bool {
        role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String
    }

    private func shouldTrustAXValue(_ value: String, appName: String, role: String?) -> Bool {
        guard !value.isEmpty else { return true }
        guard value.count <= 8_000 else { return false }
        guard !TerminalApps.isTerminal(appName: appName) else { return false }
        return isEditableTextRole(role)
    }

    private func axElement(from ref: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    private func axValue(from ref: AnyObject?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXValue.self)
    }
}
