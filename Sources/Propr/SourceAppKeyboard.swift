import AppKit

/// Drives another application by synthesising keystrokes and borrowing the pasteboard.
///
/// This is the fallback used when the Accessibility API will not give us the focused
/// text directly — most often terminals, which expose their whole transcript as an
/// editable value rather than the prompt the user is typing into.
///
/// Context is read in priority order: the user's own selection first (⌘C, inert when
/// nothing is selected), then the whole field (⌘A then ⌘C). If neither yields
/// anything there is simply no context, and the user can still ask for text to be
/// generated at the cursor.
///
/// Selecting someone's whole document is the dangerous step, so the selection is
/// collapsed again on *every* exit path — see `copyCurrentInput`. Beyond that the
/// pasteboard is saved and restored, captured text is size-capped, and Propr refuses
/// to target itself or pid 0.
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

    /// Pacing for synthesised keystrokes.
    ///
    /// Some delay is genuinely required: posting CGEvents faster than the target app
    /// drains its event queue drops characters. But a flat delay makes long text
    /// unusable — 3,000 characters at 18ms is nearly a minute of the user watching
    /// their editor type by itself.
    private enum Pacing {
        /// Comfortable spacing, used when the text is short enough to afford it.
        static let relaxed = Duration.milliseconds(18)
        /// Never go below this; apps start dropping events.
        static let floor = Duration.milliseconds(3)
        /// Roughly how long a whole run should take before pacing is compressed.
        static let budget = Duration.seconds(4)
    }

    /// The delay to use between keystrokes for a run of `count` characters.
    ///
    /// Short text keeps the relaxed spacing. Longer text is compressed so the run fits
    /// the budget, down to the floor — past that, length simply costs time.
    static func keystrokeDelay(forCharacterCount count: Int) -> Duration {
        guard count > 1 else { return Pacing.relaxed }

        let budgetNanos = Pacing.budget.nanoseconds / Int64(count)
        let relaxedNanos = Pacing.relaxed.nanoseconds
        let floorNanos = Pacing.floor.nanoseconds

        return .nanoseconds(max(floorNanos, min(relaxedNanos, budgetNanos)))
    }

    /// Virtual key codes, which are positional rather than character-based.
    private enum Key {
        static let a: CGKeyCode = 0x00
        static let c: CGKeyCode = 0x08
        static let rightArrow: CGKeyCode = 0x7C
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

    /// Selects the whole field and copies it, to use as context when the user has not
    /// selected anything themselves.
    ///
    /// Returns nil when the field is empty or its contents exceed the size cap; both
    /// mean "no context" rather than partial context, because a capture taken here
    /// implies the apply will select-all and replace — so rewriting from a truncated
    /// copy would overwrite the full text with a partial answer.
    func copyCurrentInput() async -> String? {
        print("[Propr Bar] fallback: trying select-all copy from pid=\(pid)")
        guard isTargetable else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []

        activate()
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(Key.a) else { return nil }

        // Everything in the field is now selected, which is one keystroke away from
        // destroying the user's work. Collapse it again however this function exits.
        // An arrow key does that reliably in text controls; Escape, which this used to
        // send, is not a deselect key on macOS and frequently left the selection live.
        defer { sendPlainKey(Key.rightArrow) }

        try? await Task.sleep(for: .milliseconds(60))
        guard sendCommandKey(Key.c) else {
            restorePasteboard(savedItems)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        restorePasteboard(savedItems)

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard copied.count <= Self.maxCapturedCharacters else {
            print(
                "[Propr Bar] select-all copy too large (\(copied.count) chars) — treating as no context"
            )
            return nil
        }

        print("[Propr Bar] Captured field contents via select-all copy (\(copied.count) chars)")
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

        let delay = Self.keystrokeDelay(forCharacterCount: text.count)
        for character in text {
            guard !Task.isCancelled else { return false }
            guard sendUnicodeText(String(character)) else { return false }
            try? await Task.sleep(for: delay)
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

extension Duration {
    /// Whole nanoseconds, for arithmetic on delays.
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
