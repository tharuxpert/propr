import AppKit
@preconcurrency import ApplicationServices
import Combine
import SwiftUI

/// Custom panel that can become key so SwiftUI TextFields inside can receive keyboard input.
/// We still keep nonactivatingPanel style so it doesn't steal activation from the original app aggressively.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private enum TextApplyStrategy {
    case accessibility
    case clipboardPaste
}

private enum TextApplyError: LocalizedError {
    case cannotWriteAX
    case cannotPaste
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .cannotWriteAX:
            return "Could not update the focused text field directly."
        case .cannotPaste:
            return "Could not paste or type the generated text into the source app."
        case .requestTimedOut:
            return "The model request timed out. Try again or choose a faster model."
        }
    }
}

/// Controls the floating refinement bar (NSPanel + SwiftUI content).
///
/// - Shown centered on screen when the user summons it; it never appears on its own.
/// - Non-activating where possible so it doesn't steal focus from the source app.
/// - Captures the live AX element at show time for later "apply with typing" operations.
/// - All AX element mutation for apply happens here.
@MainActor
final class FloatingBarController {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<AnyView>?

    private weak var detector: FocusedFieldDetector?
    private var sessionState = FloatingBarSessionState()
    private var refineTask: Task<Void, Never>?

    /// Keeps the panel sized to its content. The bar grows when a wrapped error
    /// message appears, which a fixed panel height would otherwise clip.
    private var sessionStateCancellable: AnyCancellable?

    /// The AX element we will write results back into. Captured when we first show the bar for a field.
    private var applyTargetElement: AXUIElement?
    private var applyTargetPID: pid_t = 0
    private var applyStrategy: TextApplyStrategy = .clipboardPaste

    /// Snapshot the bar is currently showing for (drives the header + preview).
    private var currentSnapshot: FieldSnapshot?

    // Undo support
    private var undoOriginalText: String?
    private var undoElement: AXUIElement?
    private var undoSourcePID: pid_t = 0

    // Used to force SwiftUI view recreation on every summon (resets @State)
    private var summonID = UUID()

    /// Whether the bar is currently visible.
    private(set) var isVisible: Bool = false

    init(detector: FocusedFieldDetector) {
        self.detector = detector
    }

    // MARK: - Public API

    /// Summon the floating bar (centered on screen). Captures the currently focused text field.
    func summon() {
        detector?.refreshCurrentFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                // Always center when summoned, regardless of where the field is.
                // For fallback targets like Warp, capture selected/current input *before*
                // the Propr panel becomes key; after that the source app selection/focus
                // can already be gone.
                let baseSnapshot =
                    self.detector?.currentField ?? self.snapshotForCurrentFocusedElement()
                if let baseSnapshot {
                    let prepared = await self.prepareSnapshotForSummon(baseSnapshot)
                    if prepared.isWorthShowing {
                        self.showCentered(for: prepared)
                    } else {
                        self.showCenteredEmpty()
                    }
                } else {
                    self.showCenteredEmpty()
                }
            }
        }
    }

    /// Legacy name kept for the menu/hotkey call site
    func summonForCurrentFocus() {
        summon()
    }

    /// Hide the floating bar and clear any captured target.
    func hide() {
        guard isVisible else { return }
        refineTask?.cancel()
        refineTask = nil
        sessionStateCancellable = nil
        panel?.orderOut(nil)
        isVisible = false
        currentSnapshot = nil

        // Clear undo state when the bar is dismissed
        undoOriginalText = nil
        undoElement = nil
        undoSourcePID = 0
    }

    // MARK: - Show / Position

    private func snapshotForCurrentFocusedElement() -> FieldSnapshot? {
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

    private func prepareSnapshotForSummon(_ snapshot: FieldSnapshot) async -> FieldSnapshot {
        let element = captureCurrentFocusedElement()
        let pid = targetPID(from: element, fallback: snapshot.pid)
        let strategy = strategy(for: element, role: snapshot.role, appName: snapshot.appName)

        guard strategy == .clipboardPaste, pid != 0 else {
            return snapshot
        }

        if snapshot.selectedText?.isEmpty == false {
            return snapshot
        }

        if let selectedText = await copySelectedTextFromSourceApp(pid: pid) {
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

        if let currentInput = await copyCurrentInputFromSourceApp(pid: pid) {
            print(
                "[Propr Bar] summon fallback: captured current input (\(currentInput.count) chars)")
            return FieldSnapshot(
                appName: snapshot.appName,
                pid: snapshot.pid,
                fullText: currentInput,
                selectedText: nil,
                role: snapshot.role
            )
        }

        return snapshot
    }

    private func showCentered(for snapshot: FieldSnapshot) {
        print("[Propr Bar] summon — showing centered for \(snapshot.appName)")

        // Fresh ID so SwiftUI recreates the view and resets all @State (prompt, hasApplied, etc.)
        summonID = UUID()
        sessionState = FloatingBarSessionState()

        applyTargetElement = captureCurrentFocusedElement()
        applyTargetPID = targetPID(from: applyTargetElement, fallback: snapshot.pid)
        applyStrategy = strategy(
            for: applyTargetElement, role: snapshot.role, appName: snapshot.appName)
        logTarget(snapshot: snapshot)
        currentSnapshot = snapshot

        ensurePanelExists()
        guard let panel, let hosting = hostingView else { return }

        let view = AnyView(
            FloatingBarView(
                snapshot: snapshot,
                sessionState: sessionState,
                onRefine: { [weak self] prompt in
                    self?.performRefine(context: prompt, snapshot: snapshot)
                },
                onClose: { [weak self] in self?.hide() },
                onUndo: { [weak self] in self?.undoLastApply() }
            )
            .id(summonID)
        )

        hosting.rootView = view
        hosting.setFrameSize(viewSize(for: snapshot))

        sizePanelToFitContent(recenter: true)
        observeSessionStateForResizing()

        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    private func showCenteredEmpty() {
        // Show even without a strong field (user can still give instructions)
        let dummy = FieldSnapshot(
            appName: "—", pid: 0, fullText: "", selectedText: nil, role: nil)

        summonID = UUID()
        sessionState = FloatingBarSessionState()

        applyTargetElement = captureCurrentFocusedElement()
        applyTargetPID = targetPID(from: applyTargetElement, fallback: dummy.pid)
        applyStrategy = strategy(for: applyTargetElement, role: dummy.role, appName: dummy.appName)
        logTarget(snapshot: dummy)
        currentSnapshot = dummy

        ensurePanelExists()
        guard let panel, let hosting = hostingView else { return }

        let view = AnyView(
            FloatingBarView(
                snapshot: dummy,
                sessionState: sessionState,
                onRefine: { [weak self] prompt in
                    self?.performRefine(context: prompt, snapshot: dummy)
                },
                onClose: { [weak self] in self?.hide() },
                onUndo: { [weak self] in self?.undoLastApply() }
            )
            .id(summonID)
        )

        hosting.rootView = view
        hosting.setFrameSize(viewSize(for: dummy))

        sizePanelToFitContent(recenter: true)
        observeSessionStateForResizing()

        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    /// Resizes the panel to whatever height its SwiftUI content currently needs.
    ///
    /// - Parameter recenter: `true` on first show. On later updates the top edge is
    ///   pinned instead, so the bar grows downward rather than jumping under the
    ///   cursor when an error appears.
    private func sizePanelToFitContent(recenter: Bool) {
        guard let panel, let hosting = hostingView else { return }

        hosting.layoutSubtreeIfNeeded()

        // The panel only ever grows past its base size. fittingSize under-reports
        // immediately after rootView is swapped — SwiftUI has not laid the content
        // out yet — and trusting it there collapses the bar onto its text field.
        let base = baseContentSize
        let size = NSSize(
            width: base.width,
            height: max(base.height, ceil(hosting.fittingSize.height))
        )

        guard size != panel.frame.size || recenter else { return }

        if recenter {
            centerPanel(size: size)
        } else {
            // Grow downward: keep the top edge put. AppKit origins are bottom-left.
            let current = panel.frame
            let origin = CGPoint(x: current.origin.x, y: current.maxY - size.height)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        hosting.setFrameSize(size)
    }

    /// Watches the session state so the panel can grow/shrink as content changes.
    private func observeSessionStateForResizing() {
        sessionStateCancellable = sessionState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the value is applied, so resize on
                // the next runloop pass once SwiftUI has rendered the new content.
                DispatchQueue.main.async {
                    self?.sizePanelToFitContent(recenter: false)
                }
            }
    }

    private func centerPanel(size: NSSize) {
        guard let screen = NSScreen.main else {
            panel?.setFrame(NSRect(origin: .zero, size: size), display: true)
            return
        }

        let screenFrame = screen.visibleFrame
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        panel?.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func ensurePanelExists() {
        guard panel == nil else { return }

        // Provisional; sizePanelToFitContent settles the real size once content exists.
        let contentRect = NSRect(origin: .zero, size: baseContentSize)

        let newPanel = FloatingPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        newPanel.hidesOnDeactivate = false
        newPanel.hasShadow = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.ignoresMouseEvents = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true  // makes the whole bar draggable

        // We rely on .nonactivatingPanel style + not calling makeKeyAndOrderFront in ways that activate us.
        // canBecomeKey is get-only on NSWindow in this SDK; the style mask is the correct signal.

        let hosting = NSHostingView<AnyView>(
            rootView: AnyView(
                FloatingBarView(
                    snapshot: FieldSnapshot(
                        appName: "—", pid: 0, fullText: "", selectedText: nil,
                        role: nil),
                    sessionState: sessionState,
                    onRefine: { _ in },
                    onClose: {},
                    onUndo: nil
                )))
        hosting.frame = contentRect

        newPanel.contentView = hosting

        self.panel = newPanel
        self.hostingView = hosting
    }

    /// The bar's resting size: comfortable enough for the header, context field and
    /// the status/action row. `sizePanelToFitContent` grows past this when needed
    /// (a wrapped error message) but never below it.
    private var baseContentSize: NSSize { NSSize(width: 510, height: 196) }

    private func viewSize(for snapshot: FieldSnapshot) -> NSSize {
        baseContentSize
    }

    // MARK: - AX Target Capture

    private func captureCurrentFocusedElement() -> AXUIElement? {
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

    private func axElement(from ref: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    private func targetPID(from element: AXUIElement?, fallback: pid_t) -> pid_t {
        var pid = fallback
        if let element {
            AXUIElementGetPid(element, &pid)
        }
        return pid
    }

    private func strategy(for element: AXUIElement?, role: String?, appName: String)
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

    private func isEditableTextRole(_ role: String?) -> Bool {
        role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String
    }

    private func isTerminalLikeApp(_ appName: String) -> Bool {
        let lowered = appName.lowercased()
        return lowered.contains("warp")
            || lowered.contains("terminal")
            || lowered.contains("iterm")
            || lowered.contains("ghostty")
            || lowered.contains("wezterm")
            || lowered.contains("alacritty")
            || lowered.contains("kitty")
    }

    private func logTarget(snapshot: FieldSnapshot) {
        print(
            "[Propr Bar] target app=\(snapshot.appName) pid=\(applyTargetPID) role=\(snapshot.role ?? "nil") strategy=\(applyStrategy) selected=\(snapshot.selectedText?.count ?? 0) value=\(snapshot.fullText.count)"
        )
    }

    // MARK: - Apply logic (smooth typing-style)

    private func performRefine(context: String, snapshot: FieldSnapshot) {
        let element = applyTargetElement ?? captureCurrentFocusedElement()
        let targetPID = targetPID(from: element, fallback: applyTargetPID)
        let strategy = element == nil ? .clipboardPaste : applyStrategy

        refineTask?.cancel()
        refineTask = Task { @MainActor in
            do {
                guard let selection = ModelStore.shared.selectedModel() else {
                    sessionState.fail("No model selected. Add one in Settings.")
                    return
                }

                let key = ModelStore.shared.apiKey(for: selection.endpointID) ?? ""
                if selection.requiresAPIKey
                    && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    sessionState.fail(
                        "No API key found for the selected model. Add it in Settings.")
                    return
                }

                let selectedText =
                    snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : ""
                let hasSelection = !selectedText.isEmpty
                let originalText = sanitizedModelContext(
                    hasSelection ? selectedText : snapshot.fullText)

                switch strategy {
                case .accessibility:
                    guard let element else {
                        throw TextApplyError.cannotWriteAX
                    }
                    self.undoOriginalText = originalText
                    self.undoElement = element
                    self.undoSourcePID = 0
                    try await applyWithAccessibilityStreaming(
                        originalText: originalText,
                        instruction: context,
                        selection: selection,
                        apiKey: key,
                        element: element,
                        replaceSelectionOnly: hasSelection
                    )

                case .clipboardPaste:
                    self.undoOriginalText = nil
                    self.undoElement = nil
                    self.undoSourcePID = targetPID
                    try await applyWithClipboardPaste(
                        originalText: originalText,
                        instruction: context,
                        selection: selection,
                        apiKey: key,
                        targetPID: targetPID,
                        replaceExistingInput: !hasSelection && !originalText.isEmpty
                    )
                }
            } catch {
                print("AI refinement failed: \(error)")
                sessionState.fail(error.localizedDescription)
                // Never write error text into the target application
            }
        }
    }

    private func applyWithAccessibilityStreaming(
        originalText: String,
        instruction: String,
        selection: ModelSelection,
        apiKey: String,
        element: AXUIElement,
        replaceSelectionOnly: Bool
    ) async throws {
        var firstToken = true

        for try await token in AIService.shared.refineStream(
            original: originalText,
            instruction: instruction,
            selection: selection,
            apiKey: apiKey
        ) {
            guard !Task.isCancelled else { return }

            if firstToken {
                firstToken = false
                sessionState.startTyping()
                try prepareAccessibilityTargetForReplacement(
                    element,
                    replaceWholeValue: !replaceSelectionOnly && !originalText.isEmpty
                )
                try? await Task.sleep(for: .milliseconds(25))
            }

            try await appendTokenWithTyping(token, into: element)
        }

        if firstToken {
            sessionState.fail("The model returned an empty response.")
        } else {
            sessionState.finishRequest()
        }
    }

    private func applyWithClipboardPaste(
        originalText: String,
        instruction: String,
        selection: ModelSelection,
        apiKey: String,
        targetPID: pid_t,
        replaceExistingInput: Bool
    ) async throws {
        let result = try await withTimeout(seconds: 45) {
            try await AIService.shared.refine(
                original: originalText,
                instruction: instruction,
                selection: selection,
                apiKey: apiKey
            )
        }
        guard !Task.isCancelled else { return }
        guard !result.isEmpty else {
            sessionState.fail("The model returned an empty response.")
            return
        }

        sessionState.startTyping()
        let typed = await typeTextIntoSourceApp(
            result,
            pid: targetPID,
            replaceExistingInput: replaceExistingInput
        )
        guard typed else { throw TextApplyError.cannotPaste }
        sessionState.finishRequest()
    }

    func undoLastApply() {
        if undoElement == nil, undoSourcePID != 0 {
            activateSourceApp(pid: undoSourcePID)
            sendCommandKey(virtualKey: 0x06, pid: undoSourcePID)  // Z
            hide()
            return
        }

        guard let element = undoElement,
            let originalText = undoOriginalText
        else {
            hide()
            return
        }

        // Try to restore the original text cleanly
        // First select everything
        var currentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
            == .success,
            let text = currentValue as? String
        {
            let len = (text as NSString).length
            var range = CFRange(location: 0, length: len)
            if let rangeVal = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(
                    element, kAXSelectedTextRangeAttribute as CFString, rangeVal)
            }
        }

        // Replace with original
        _ = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, originalText as CFString)

        // Clear undo state
        undoOriginalText = nil
        undoElement = nil

        // Hide after a short moment so the user sees the restoration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            hide()
        }
    }

    private func prepareAccessibilityTargetForReplacement(
        _ element: AXUIElement,
        replaceWholeValue: Bool
    ) throws {
        if replaceWholeValue {
            var currentValue: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
                == .success,
                let text = currentValue as? String,
                !text.isEmpty
            {
                let len = (text as NSString).length
                var range = CFRange(location: 0, length: len)
                if let rangeVal = AXValueCreate(.cfRange, &range) {
                    AXUIElementSetAttributeValue(
                        element,
                        kAXSelectedTextRangeAttribute as CFString,
                        rangeVal
                    )
                }
            }
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

    /// Appends a token (can be multiple characters) with the same per-character typing animation.
    /// Used during live streaming so the model appears to "type as it thinks".
    private func appendTokenWithTyping(_ token: String, into element: AXUIElement) async throws {
        for character in token {
            let chunk = String(character)

            let status = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                chunk as CFString
            )
            guard status == .success else {
                throw TextApplyError.cannotWriteAX
            }

            // Faster typing speed for the live streaming "as it thinks" feel
            try? await Task.sleep(for: .milliseconds(22))
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TextApplyError.requestTimedOut
            }

            guard let result = try await group.next() else {
                throw TextApplyError.requestTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    private func sanitizedModelContext(_ text: String) -> String {
        let maxContextCharacters = 8_000
        guard text.count > maxContextCharacters else { return text }
        print("[Propr Bar] Dropping oversized context (\(text.count) chars)")
        return ""
    }

    private func copySelectedTextFromSourceApp(pid: pid_t) async -> String? {
        print("[Propr Bar] fallback: trying selected-text copy from pid=\(pid)")
        guard pid != 0, pid != getpid() else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []
        let oldString = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        activateSourceApp(pid: pid)
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(virtualKey: 0x08, pid: pid) else { return nil }  // C
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        let changed = pasteboard.changeCount != oldChangeCount || copied != oldString
        restorePasteboardItems(savedItems)

        guard changed,
            let copied,
            !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            copied.count <= 8_000
        else { return nil }
        return copied
    }

    private func copyCurrentInputFromSourceApp(pid: pid_t) async -> String? {
        print("[Propr Bar] fallback: trying select-all copy from pid=\(pid)")
        guard pid != 0, pid != getpid() else { return nil }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []

        activateSourceApp(pid: pid)
        try? await Task.sleep(for: .milliseconds(90))
        guard sendCommandKey(virtualKey: 0x00, pid: pid) else { return nil }  // A
        try? await Task.sleep(for: .milliseconds(60))
        guard sendCommandKey(virtualKey: 0x08, pid: pid) else {  // C
            restorePasteboardItems(savedItems)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.string(forType: .string)
        restorePasteboardItems(savedItems)

        guard let copied,
            !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            sendPlainKey(virtualKey: 0x35, pid: pid)  // Escape clears many transient selections.
            return nil
        }

        guard copied.count <= 8_000 else {
            print("[Propr Bar] Ignoring oversized fallback input copy (\(copied.count) chars)")
            sendPlainKey(virtualKey: 0x35, pid: pid)  // Escape clears many transient selections.
            return nil
        }

        print("[Propr Bar] Captured fallback input via select-all copy (\(copied.count) chars)")
        return copied
    }

    private func typeTextIntoSourceApp(
        _ text: String,
        pid: pid_t,
        replaceExistingInput: Bool
    ) async -> Bool {
        guard pid != 0, pid != getpid(), !text.isEmpty else { return false }

        activateSourceApp(pid: pid)
        try? await Task.sleep(for: .milliseconds(130))

        if replaceExistingInput {
            print("[Propr Bar] fallback: selecting all before typing into pid=\(pid)")
            guard sendCommandKey(virtualKey: 0x00, pid: pid) else { return false }  // A
            try? await Task.sleep(for: .milliseconds(60))
        }

        for character in text {
            guard !Task.isCancelled else { return false }
            guard sendUnicodeText(String(character), pid: pid) else { return false }
            try? await Task.sleep(for: .milliseconds(18))
        }

        return true
    }

    private func restorePasteboardItems(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func activateSourceApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    @discardableResult
    private func sendUnicodeText(_ text: String, pid: pid_t) -> Bool {
        let units = Array(text.utf16)
        guard !units.isEmpty,
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            return false
        }

        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    @discardableResult
    private func sendPlainKey(virtualKey: CGKeyCode, pid: pid_t) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else {
            return false
        }

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    @discardableResult
    private func sendCommandKey(virtualKey: CGKeyCode, pid: pid_t) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }
}
