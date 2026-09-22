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
        static let v: CGKeyCode = 0x09
        static let leftArrow: CGKeyCode = 0x7B
        static let rightArrow: CGKeyCode = 0x7C
        static let backspace: CGKeyCode = 0x33
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
        // A copy of the data, not the item objects — see PasteboardSnapshot.
        let saved = PasteboardSnapshot(of: pasteboard)
        let oldString = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        activate()
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(Key.c) else { return nil }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        // A changeCount bump alone is not proof: some apps rewrite identical contents.
        let changed = pasteboard.changeCount != oldChangeCount || copied != oldString
        saved.restore(to: pasteboard)

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
        // A copy of the data, not the item objects — see PasteboardSnapshot.
        let saved = PasteboardSnapshot(of: pasteboard)

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
            saved.restore(to: pasteboard)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)

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

    /// Pastes `text` with ⌘V, then puts the user's clipboard back. Used for terminals
    /// in place of typing.
    ///
    /// Typing a newline into a shell is pressing Return: zsh and bash both bind `^J` to
    /// `accept-line`, so a multi-line answer ran line by line as it was typed, before
    /// the user could read it and past the reach of Undo. A paste arrives as a
    /// *bracketed* paste instead — on by default in zsh, macOS's default shell — which
    /// goes into the command buffer whole, newlines and all, and runs nothing until the
    /// user presses Return. (macOS's own /bin/bash 3.2 has no bracketed paste, so a
    /// user who has switched to it would still see lines run.)
    ///
    /// The clipboard is borrowed for the paste and restored afterwards, marked as
    /// transient so clipboard managers leave it out of the user's history.
    func paste(_ text: String) async -> Bool {
        guard isTargetable, !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(of: pasteboard)

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // nspasteboard.org markers: this content is momentary and app-generated, so
        // clipboard history tools should not record it.
        item.setData(Data(), forType: Self.transientMarker)
        item.setData(Data(), forType: Self.autoGeneratedMarker)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            saved.restore(to: pasteboard)
            return false
        }

        activate()
        try? await Task.sleep(for: .milliseconds(130))

        guard sendCommandKey(Key.v) else {
            saved.restore(to: pasteboard)
            return false
        }

        // There is no callback for "the app has read the pasteboard", so wait long
        // enough for it to. Restoring early would paste the user's old clipboard
        // instead of the answer.
        //
        // Waited in a separate task: closing the bar cancels the refine, and a
        // cancelled sleep returns at once — which would restore too soon.
        await Task { try? await Task.sleep(for: .milliseconds(500)) }.value
        saved.restore(to: pasteboard)
        return true
    }

    private static let transientMarker = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let autoGeneratedMarker = NSPasteboard.PasteboardType(
        "org.nspasteboard.AutoGeneratedType")

    /// Presses Backspace `count` times — the undo for text typed into a terminal, where
    /// ⌘Z does not work. Paced like typing, since Backspace keystrokes are just as
    /// easy for a busy app to drop.
    func deleteBackward(_ count: Int) async {
        guard isTargetable, count > 0 else { return }

        activate()
        try? await Task.sleep(for: .milliseconds(130))

        let delay = Self.keystrokeDelay(forCharacterCount: count)
        for _ in 0..<count {
            guard !Task.isCancelled else { return }
            guard sendPlainKey(Key.backspace) else { return }
            try? await Task.sleep(for: delay)
        }
    }

    /// Moves through text already inserted by Propr. This is the fallback for apps
    /// where Accessibility cannot set an exact selected-text range.
    func moveCaretLeft(_ count: Int) async -> Bool {
        await moveCaret(using: Key.leftArrow, count: count)
    }

    func moveCaretRight(_ count: Int) async -> Bool {
        await moveCaret(using: Key.rightArrow, count: count)
    }

    /// Sends ⌘Z, used to undo an applied refinement in apps written to via keystrokes.
    func sendUndo() {
        guard isTargetable else { return }
        activate()
        sendCommandKey(0x06)  // Z
    }

    private func moveCaret(using key: CGKeyCode, count: Int) async -> Bool {
        guard isTargetable else { return false }
        guard count > 0 else { return true }

        activate()
        // Match the proven paste/type activation window. Terminal apps such as Warp
        // can still be switching focus from Propr when a shorter delay expires.
        try? await Task.sleep(for: .milliseconds(130))

        let delay = Self.keystrokeDelay(forCharacterCount: count)
        for _ in 0..<count {
            guard !Task.isCancelled, sendPlainKey(key) else { return false }
            try? await Task.sleep(for: delay)
        }
        return true
    }

    // MARK: - Primitives

    func activate() {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func isUsable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= Self.maxCapturedCharacters
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
