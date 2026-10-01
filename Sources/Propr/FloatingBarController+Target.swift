import AppKit
@preconcurrency import ApplicationServices

// Working out what the bar is pointed at: reading the focused element, and deciding
// whether its text can be written through the Accessibility API or has to go via
// synthesised keystrokes.
extension FloatingBarController {
    // MARK: - Show / Position

    // MARK: - AX Target Capture

    func captureCurrentFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success,
            let axRef = focused,
            let element = axElement(from: axRef)
        else {
            print(
                "[Propr Bar] captureCurrentFocusedElement failed (result=\(result.rawValue)) — no AX element to target for apply"
            )
            return nil
        }
        return element
    }

    func axElement(from ref: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    func targetPID(from element: AXUIElement?, fallback: pid_t) -> pid_t {
        var pid = fallback
        if let element {
            AXUIElementGetPid(element, &pid)
        }
        return pid
    }

    /// The process generated text should be written back into.
    ///
    /// Prefers the owner of the focused accessibility element. When AX gives us
    /// nothing — the same situation that makes the bar fall back to its placeholder
    /// snapshot — it uses the frontmost application instead. Without this the pid
    /// stays 0, `SourceAppKeyboard` refuses to drive it, and asking for text to be
    /// generated at the cursor fails at the last step with "could not type".
    ///
    /// Must be called before the panel takes key focus, so the frontmost application
    /// is still the user's and not Propr. Propr's own pid is never returned.
    func resolveTargetPID(from element: AXUIElement?, fallback: pid_t) -> pid_t {
        let fromElement = targetPID(from: element, fallback: fallback)
        if fromElement != 0, fromElement != getpid() {
            return fromElement
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            frontmost != 0, frontmost != getpid()
        {
            print("[Propr Bar] no AX element — falling back to frontmost app pid=\(frontmost)")
            return frontmost
        }

        return fromElement
    }

    func strategy(for element: AXUIElement?, role: String?, appName: String)
        -> TextApplyStrategy
    {
        // Terminal-style apps often claim AX text editability while exposing the
        // transcript/window instead of the real prompt. Always use the fallback
        // key-event path for them.
        guard !TerminalApps.isTerminal(appName: appName), let element, isEditableTextRole(role) else {
            return .clipboardPaste
        }

        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        return status == .success && settable.boolValue ? .accessibility : .clipboardPaste
    }

    func isEditableTextRole(_ role: String?) -> Bool {
        role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String
    }


    func logTarget(snapshot: FieldSnapshot) {
        print(
            "[Propr Bar] target app=\(snapshot.appName) pid=\(applyTargetPID) role=\(snapshot.role ?? "nil") strategy=\(applyStrategy) selected=\(snapshot.selectedText?.count ?? 0) value=\(snapshot.fullText.count)"
        )
    }

}
