import AppKit

/// Drives another application by synthesising keystrokes and borrowing the pasteboard.
///
/// This is the fallback used when the Accessibility API will not give us the focused
/// text directly — most often terminals, which expose their whole transcript as an
/// editable value rather than the prompt the user is typing into.
///
/// It is the most invasive thing Propr does: reading context means sending ⌘A/⌘C to
/// an app Propr does not own, and writing means typing into it character by character.
/// Every step is therefore conservative — the pasteboard is saved and restored, the
/// captured text is size-capped, and Propr refuses to target itself or pid 0.
///
/// The waits between steps are unavoidable: there is no completion callback for a
/// synthetic keystroke, so we can only give the target app a moment to react. They are
/// the weakest part of this approach and the reason it is a fallback, not the default.
@MainActor
struct SourceAppKeyboard {
    /// The process being driven.
    let pid: pid_t

    /// Text longer than this is refused rather than sent to a model.
    private static let maxCapturedCharacters = 8_000

    /// Virtual key codes, which are positional rather than character-based.
    private enum Key {
        static let a: CGKeyCode = 0x00
        static let c: CGKeyCode = 0x08
        static let escape: CGKeyCode = 0x35
    }

    /// Whether this is a process we are willing to drive.
    private var isTargetable: Bool {
        pid != 0 && pid != getpid()
    }

    // MARK: - Reading

    /// Copies the current selection, restoring the pasteboard afterwards.
    /// Returns nil when nothing was selected or the copy did not take effect.
    func copySelectedText() async -> String? {
        print("[Propr Bar] fallback: trying selected-text copy from pid=\(pid)")
        guard isTargetable else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []
        let oldString = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        activate()
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(Key.c) else { return nil }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        // A changeCount bump alone is not proof: some apps rewrite identical contents.
        let changed = pasteboard.changeCount != oldChangeCount || copied != oldString
        restorePasteboard(savedItems)

        guard changed, let copied, isUsable(copied) else { return nil }
        return copied
    }

    /// Selects all and copies, to capture what the user has typed so far.
    /// Sends Escape on failure, which clears the selection in most apps.
    func copyCurrentInput() async -> String? {
        print("[Propr Bar] fallback: trying select-all copy from pid=\(pid)")
        guard isTargetable else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []

        activate()
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(Key.a) else { return nil }
        try? await Task.sleep(for: .milliseconds(60))
        guard sendCommandKey(Key.c) else {
            restorePasteboard(savedItems)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        restorePasteboard(savedItems)

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendPlainKey(Key.escape)
            return nil
        }

        guard copied.count <= Self.maxCapturedCharacters else {
            print("[Propr Bar] Ignoring oversized fallback input copy (\(copied.count) chars)")
            sendPlainKey(Key.escape)
            return nil
        }

        print("[Propr Bar] Captured fallback input via select-all copy (\(copied.count) chars)")
        return copied
    }

    // MARK: - Writing

    /// Types `text` one character at a time, optionally replacing what is already there.
    /// Returns false if the run was cancelled or a keystroke could not be delivered.
    func type(_ text: String, replacingExistingInput: Bool) async -> Bool {
        guard isTargetable, !text.isEmpty else { return false }

        activate()
        try? await Task.sleep(for: .milliseconds(130))

        if replacingExistingInput {
            print("[Propr Bar] fallback: selecting all before typing into pid=\(pid)")
            guard sendCommandKey(Key.a) else { return false }
            try? await Task.sleep(for: .milliseconds(60))
        }

        for character in text {
            guard !Task.isCancelled else { return false }
            guard sendUnicodeText(String(character)) else { return false }
            try? await Task.sleep(for: .milliseconds(18))
        }

        return true
    }

    /// Sends ⌘Z, used to undo an applied refinement in apps written to via keystrokes.
    func sendUndo() {
        guard isTargetable else { return }
        activate()
        sendCommandKey(0x06)  // Z
    }

    // MARK: - Primitives

    func activate() {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func isUsable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= Self.maxCapturedCharacters
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    /// Posts text as a unicode keystroke, so it does not depend on the user's layout.
    @discardableResult
    private func sendUnicodeText(_ text: String) -> Bool {
        let units = Array(text.utf16)
        guard !units.isEmpty,
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            return false
        }

        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    @discardableResult
    private func sendPlainKey(_ virtualKey: CGKeyCode) -> Bool {
        sendKey(virtualKey, flags: [])
    }

    @discardableResult
    private func sendCommandKey(_ virtualKey: CGKeyCode) -> Bool {
        sendKey(virtualKey, flags: .maskCommand)
    }

    @discardableResult
    private func sendKey(_ virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }
}
