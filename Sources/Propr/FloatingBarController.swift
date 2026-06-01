import SwiftUI
import AppKit
@preconcurrency import ApplicationServices
import Combine

/// Custom panel that can become key so SwiftUI TextFields inside can receive keyboard input.
/// We still keep nonactivatingPanel style so it doesn't steal activation from the original app aggressively.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Controls the floating refinement bar (NSPanel + SwiftUI content).
/// 
/// - Appears near a detected text field when the FocusedFieldDetector publishes a snapshot.
/// - Non-activating where possible so it doesn't steal focus from the source app.
/// - Captures the live AX element at show time for later "apply with typing" operations.
/// - All AX element mutation for apply happens here.
@MainActor
final class FloatingBarController {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<AnyView>?

    private weak var detector: FocusedFieldDetector?
    /// The AX element we will write results back into. Captured when we first show the bar for a field.
    private var applyTargetElement: AXUIElement?

    /// Snapshot we showed for (used for positioning + UI state).
    private var currentSnapshot: FieldSnapshot?

    // Undo support
    private var undoOriginalText: String?
    private var undoElement: AXUIElement?

    // Latest closures from the current FloatingBarView instance for loading/error states
    private var latestOnStopThinking: (() -> Void)?
    private var latestStartTyping: (() -> Void)?
    private var latestStopTyping: (() -> Void)?
    private var latestShowError: ((String) -> Void)?

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

            // Always center when summoned, regardless of where the field is
            if let snap = self.detector?.currentField, snap.isWorthShowing {
                self.showCentered(for: snap)
            } else {
                // Even if no good field, still show the bar centered (user can still type instructions)
                self.showCenteredEmpty()
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
        panel?.orderOut(nil)
        isVisible = false
        currentSnapshot = nil

        // Clear undo state when the bar is dismissed
        undoOriginalText = nil
        undoElement = nil
    }

    // MARK: - Show / Position

    private func show(for snapshot: FieldSnapshot) {
        print("[Propr Bar] show(for:) called — positioning near \(snapshot.appName) at \(snapshot.frame.origin)")

        // Capture a fresh AX element for apply right now (the one the detector just saw).
        applyTargetElement = captureCurrentFocusedElement()

        currentSnapshot = snapshot

        ensurePanelExists()

        guard let panel, let hosting = hostingView else { return }

        // Update the SwiftUI view with fresh data
        summonID = UUID()

        let view = AnyView(
            FloatingBarView(
                snapshot: snapshot,
                onQuickAction: { [weak self] action in
                    self?.handleQuickAction(action, snapshot: snapshot)
                },
                onRefine: { [weak self] customContext in
                    self?.performRefine(context: customContext, snapshot: snapshot)
                },
                onClose: { [weak self] in
                    self?.hide()
                },
                onUndo: { [weak self] in self?.undoLastApply() },
                onThinkingStarted: { [weak self] in
                    // View already calls startThinking() on submit.
                },
                onStopThinking: { [weak self] in
                    self?.latestOnStopThinking?()
                    self?.latestOnStopThinking = nil
                },
                onError: { [weak self] message in
                    self?.latestShowError?(message)
                },
                onTypingStarted: { [weak self] in
                    self?.latestStartTyping?()
                },
                onTypingFinished: { [weak self] in
                    self?.latestStopTyping?()
                }
            )
            .id(summonID)
        )

        hosting.rootView = view
        hosting.setFrameSize(viewSize(for: snapshot))

        positionPanel(near: snapshot.frame, panelSize: hosting.frame.size)

        if !panel.isVisible {
            panel.alphaValue = 0
            // Use orderFront (not makeKeyAndOrderFront) so we don't steal key/activation from the target app.
            panel.orderFront(nil)
            // Subtle fade in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFront(nil)
        }

        isVisible = true

        // Keep the source app active if possible (non-activating panel helps)
        // We do NOT call NSApp.activate here on purpose.
    }

    private func showCentered(for snapshot: FieldSnapshot) {
        print("[Propr Bar] summon — showing centered for \(snapshot.appName)")

        // Fresh ID so SwiftUI recreates the view and resets all @State (prompt, hasApplied, etc.)
        summonID = UUID()

        applyTargetElement = captureCurrentFocusedElement()
        currentSnapshot = snapshot

        ensurePanelExists()
        guard let panel, let hosting = hostingView else { return }

        let view = AnyView(
            FloatingBarView(
                snapshot: snapshot,
                onQuickAction: { _ in },
                onRefine: { [weak self] prompt in
                    self?.performRefine(context: prompt, snapshot: snapshot)
                },
                onClose: { [weak self] in self?.hide() },
                onUndo: { [weak self] in self?.undoLastApply() },
                onThinkingStarted: {},
                onStopThinking: {},
                onError: { _ in },
                onTypingStarted: { [weak self] in self?.latestStartTyping?() },
                onTypingFinished: { [weak self] in self?.latestStopTyping?() }
            )
            .id(summonID)
        )

        hosting.rootView = view
        hosting.setFrameSize(viewSize(for: snapshot))

        centerPanel(size: hosting.frame.size)

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
        let dummy = FieldSnapshot(appName: "—", pid: 0, fullText: "", selectedText: nil, frame: .zero, role: nil)

        summonID = UUID()

        applyTargetElement = captureCurrentFocusedElement()
        currentSnapshot = dummy

        ensurePanelExists()
        guard let panel, let hosting = hostingView else { return }

        let view = AnyView(
            FloatingBarView(
                snapshot: dummy,
                onQuickAction: { _ in },
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

        centerPanel(size: hosting.frame.size)

        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        isVisible = true
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

        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 140)

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
        newPanel.isMovableByWindowBackground = true   // makes the whole bar draggable

        // We rely on .nonactivatingPanel style + not calling makeKeyAndOrderFront in ways that activate us.
        // canBecomeKey is get-only on NSWindow in this SDK; the style mask is the correct signal.

        let hosting = NSHostingView<AnyView>(rootView: AnyView(FloatingBarView(
            snapshot: FieldSnapshot(appName: "—", pid: 0, fullText: "", selectedText: nil, frame: .zero, role: nil),
            onQuickAction: { _ in },
            onRefine: { _ in },
            onClose: {},
            onUndo: nil,
            onThinkingStarted: {},
            onStopThinking: {},
            onError: { _ in },
            onTypingStarted: { [weak self] in self?.latestStartTyping?() },
            onTypingFinished: { [weak self] in self?.latestStopTyping?() }
        )))
        hosting.frame = contentRect

        newPanel.contentView = hosting

        self.panel = newPanel
        self.hostingView = hosting
    }

    private func viewSize(for snapshot: FieldSnapshot) -> NSSize {
        // Dynamic-ish height based on content; start generous and let SwiftUI compress.
        // For v1 we use a fixed comfortable size that fits the chips + context field.
        NSSize(width: 460, height: 168)
    }

    private func positionPanel(near fieldFrame: CGRect, panelSize: NSSize) {
        guard let screen = NSScreen.main else {
            panel?.setFrame(NSRect(origin: .zero, size: panelSize), display: true)
            return
        }

        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 12

        // Prefer above the field; fall back below if not enough room.
        var originX = fieldFrame.midX - panelSize.width / 2
        var originY = fieldFrame.minY - panelSize.height - margin

        // Clamp horizontally
        originX = max(screenFrame.minX + margin, min(originX, screenFrame.maxX - panelSize.width - margin))

        if originY < screenFrame.minY + margin {
            // Not enough room above — put it below the field instead
            originY = fieldFrame.maxY + margin
        }

        // Final vertical clamp
        originY = max(screenFrame.minY + margin, min(originY, screenFrame.maxY - panelSize.height - margin))

        let targetRect = NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height)
        panel?.setFrame(targetRect, display: true)
    }

    // MARK: - AX Target Capture

    private func captureCurrentFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let axRef = focused else {
            print("[Propr Bar] captureCurrentFocusedElement failed (result=\(result.rawValue)) — no AX element to target for apply")
            return nil
        }
        // AXUIElement is toll-free bridged; after a successful attribute read the type is guaranteed.
        let element = unsafeDowncast(axRef, to: AXUIElement.self)
        return element
    }

    // MARK: - Apply logic (smooth typing-style)

    private func performRefine(context: String, snapshot: FieldSnapshot) {
        guard let element = applyTargetElement ?? captureCurrentFocusedElement() else {
            hide()
            return
        }

        // Save undo state *before* we mutate anything
        let originalText = snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : snapshot.fullText
        self.undoOriginalText = originalText
        self.undoElement = element

        Task { @MainActor in
            do {
                guard let selection = ModelStore.shared.selectedModel() else {
                    latestOnStopThinking?()
                    latestStopTyping?()
                    // Report error to the floating bar instead of polluting the text field
                    // We need the onError closure to be wired from the view
                    print("[Propr] No model selected")
                    return
                }

                guard let key = ModelStore.shared.apiKey(for: selection.endpointID) else {
                    latestOnStopThinking?()
                    latestStopTyping?()
                    latestShowError?("No API key found for the selected model. Please add it in Settings.")
                    return
                }

                // Streaming with live token-by-token typing ("typing as it thinks")
                latestOnStopThinking = nil // reset

                var fullResult = ""
                var firstToken = true

                for try await token in AIService.shared.refineStream(
                    original: originalText,
                    instruction: context,
                    selection: selection,
                    apiKey: key
                ) {
                    if firstToken {
                        firstToken = false

                        // Stop "Thinking…" and start "Typing…" indicator in the bar
                        latestOnStopThinking?()
                        latestStartTyping?()

                        // On the very first token: clear the original text first
                        var currentValue: AnyObject?
                        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
                           let text = currentValue as? String, !text.isEmpty {
                            let len = (text as NSString).length
                            var range = CFRange(location: 0, length: len)
                            if let rangeVal = AXValueCreate(.cfRange, &range) {
                                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeVal)
                            }
                        }

                        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFString)

                        // Small pause before live typing begins
                        try? await Task.sleep(for: .milliseconds(25))
                    }

                    // Live incremental typing — the model types directly into the target field
                    await appendTokenWithTyping(token, into: element)
                    fullResult += token
                }

                // Streaming finished — hide the Typing… indicator
                latestStopTyping?()

                // Stream finished. fullResult now contains the complete output.
                // (Undo state was already captured at the beginning of performRefine)

            } catch {
                print("AI refinement failed: \(error)")
                latestOnStopThinking?()
                latestStopTyping?()

                latestShowError?(error.localizedDescription)
                // Never write error text into the target application
            }
        }
    }

    private func handleQuickAction(_ action: QuickAction, snapshot: FieldSnapshot) {
        // Quick actions fill the context and immediately trigger refine with that intent.
        let context = action.defaultContext
        performRefine(context: context, snapshot: snapshot)
    }

    func undoLastApply() {
        guard let element = undoElement,
              let originalText = undoOriginalText else {
            hide()
            return
        }

        // Try to restore the original text cleanly
        // First select everything
        var currentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
           let text = currentValue as? String {
            let len = (text as NSString).length
            var range = CFRange(location: 0, length: len)
            if let rangeVal = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeVal)
            }
        }

        // Replace with original
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, originalText as CFString)

        // Clear undo state
        undoOriginalText = nil
        undoElement = nil

        // Hide after a short moment so the user sees the restoration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            hide()
        }
    }

    private func applyWithTypingAnimation(result: String, into element: AXUIElement) async {
        // Clean, visible dummy writing using AX only.
        // This is currently the most reliable way to see the typing effect
        // without triggering macOS alert sounds.

        // 1. Select the whole current field
        var currentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
           let text = currentValue as? String, !text.isEmpty {
            let len = (text as NSString).length
            var range = CFRange(location: 0, length: len)
            if let rangeVal = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeVal)
            }
        }

        // 2. Delete the old text
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFString)

        // Let the target app breathe for a moment
        try? await Task.sleep(for: .milliseconds(70))

        // 3. Progressively insert the new result, one character at a time.
        // This is the visible "writing" animation for the dummy mode.
        // Deliberately slow so you can clearly watch it type.
        for character in result {
            let chunk = String(character)

            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                chunk as CFString
            )

            // Faster typing speed (kept slightly slower than live streaming for the full-result fallback)
            try? await Task.sleep(for: .milliseconds(28))
        }
    }

    /// Appends a token (can be multiple characters) with the same per-character typing animation.
    /// Used during live streaming so the model appears to "type as it thinks".
    private func appendTokenWithTyping(_ token: String, into element: AXUIElement) async {
        for character in token {
            let chunk = String(character)

            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                chunk as CFString
            )

            // Faster typing speed for the live streaming "as it thinks" feel
            try? await Task.sleep(for: .milliseconds(22))
        }
    }
}
