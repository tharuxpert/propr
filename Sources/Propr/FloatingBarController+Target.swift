import AppKit
@preconcurrency import ApplicationServices

// Working out what the bar is pointed at: reading the focused element, and deciding
// whether its text can be written through the Accessibility API or has to go via
// synthesised keystrokes.
extension FloatingBarController {
    // MARK: - Show / Position

    func snapshotForCurrentFocusedElement() -> FieldSnapshot? {
        guard let element = captureCurrentFocusedElement() else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0, pid != getpid() else { return nil }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown App"

        return FieldSnapshot(
            appName: appName,
            pid: pid,
            fullText: "",
            selectedText: nil,
            role: role
        )
    }

    func prepareSnapshotForSummon(_ snapshot: FieldSnapshot) async -> FieldSnapshot {
        let element = captureCurrentFocusedElement()
        let pid = targetPID(from: element, fallback: snapshot.pid)
        let strategy = strategy(for: element, role: snapshot.role, appName: snapshot.appName)

        guard strategy == .clipboardPaste, pid != 0 else {
            return snapshot
        }

        if snapshot.selectedText?.isEmpty == false {
            return snapshot
        }

        // Only ⌘C. If nothing is selected there is simply no context, and the user
        // can still ask for text to be generated at the cursor.

        if let selectedText = await SourceAppKeyboard(pid: pid).copySelectedText() {
            print(
                "[Propr Bar] summon fallback: captured selected text (\(selectedText.count) chars)")
            return FieldSnapshot(
                appName: snapshot.appName,
                pid: snapshot.pid,
                fullText: "",
                selectedText: selectedText,
                role: snapshot.role
            )
        }

        return snapshot
    }

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

    func strategy(for element: AXUIElement?, role: String?, appName: String)
        -> TextApplyStrategy
    {
        // Terminal-style apps often claim AX text editability while exposing the
        // transcript/window instead of the real prompt. Always use the fallback
        // key-event path for them.
        guard !isTerminalLikeApp(appName), let element, isEditableTextRole(role) else {
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

    func isTerminalLikeApp(_ appName: String) -> Bool {
        let lowered = appName.lowercased()
        return lowered.contains("warp")
            || lowered.contains("terminal")
            || lowered.contains("iterm")
            || lowered.contains("ghostty")
            || lowered.contains("wezterm")
            || lowered.contains("alacritty")
            || lowered.contains("kitty")
    }

    func logTarget(snapshot: FieldSnapshot) {
        print(
            "[Propr Bar] target app=\(snapshot.appName) pid=\(applyTargetPID) role=\(snapshot.role ?? "nil") strategy=\(applyStrategy) selected=\(snapshot.selectedText?.count ?? 0) value=\(snapshot.fullText.count)"
        )
    }

}
