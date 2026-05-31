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
    private var detectorObservation: AnyCancellable?

    /// The AX element we will write results back into. Captured when we first show the bar for a field.
    private var applyTargetElement: AXUIElement?

    /// Snapshot we showed for (used for positioning + UI state).
    private var currentSnapshot: FieldSnapshot?

    // Undo support
    private var undoOriginalText: String?
    private var undoElement: AXUIElement?

    // Used to force SwiftUI view recreation on every summon (resets @State)
    private var summonID = UUID()

    /// Whether the bar is currently visible.
    private(set) var isVisible: Bool = false

    init(detector: FocusedFieldDetector) {
        self.detector = detector
        setupObservation()
    }

    private func setupObservation() {
        // We no longer auto-show the bar on focus changes.
        // The bar is now summon-only (via hotkey or menu).
        // We keep a no-op observation so the detector can still be used for manual capture on summon.
        detectorObservation = detector?.$currentField
            .sink { _ in }
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
                onUndo: { [weak self] in self?.undoLastApply() }
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
                onUndo: { [weak self] in self?.undoLastApply() }
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
            onUndo: nil
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

        let resultText = generateResult(from: snapshot, context: context)

        Task { @MainActor in
            await applyWithTypingAnimation(result: resultText, into: element)

            // Instead of auto-hiding immediately, switch to "applied" state with Undo
            // For now we'll keep the bar open so the user can undo
            // (We'll improve the UI in the view next)
            // try? await Task.sleep(for: .milliseconds(420))
            // hide()
        }
    }

    private func handleQuickAction(_ action: QuickAction, snapshot: FieldSnapshot) {
        // Quick actions fill the context and immediately trigger refine with that intent.
        let context = action.defaultContext
        performRefine(context: context, snapshot: snapshot)
    }

    private func generateResult(from snapshot: FieldSnapshot, context: String) -> String {
        // Temporary local transforms until real AI is wired up.
        // The goal is to demonstrate the end-to-end flow + beautiful typing animation.
        let original = snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : snapshot.fullText
        let lower = context.lowercased()

        if lower.contains("shorter") || lower.contains("concise") {
            let words = original.split(separator: " ")
            let keep = max(3, words.count * 3 / 5)
            return words.prefix(keep).joined(separator: " ") + (words.count > keep ? "…" : "")
        }

        if lower.contains("professional") || lower.contains("formal") {
            return original
                .replacingOccurrences(of: "hey", with: "Hello")
                .replacingOccurrences(of: "thanks", with: "Thank you")
                .replacingOccurrences(of: "gonna", with: "going to")
                .capitalized
        }

        if lower.contains("casual") || lower.contains("friendly") {
            return "Hey — " + original.lowercased()
        }

        if lower.contains("bullet") {
            return original
                .split(separator: ".")
                .map { "• " + $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }

        if lower.contains("fix") || lower.contains("grammar") {
            // Very naive demo "fix"
            var t = original
            if !t.hasSuffix(".") && !t.hasSuffix("!") && !t.hasSuffix("?") && !t.isEmpty {
                t += "."
            }
            return t
        }

        // Default demo transform: elegant rewrite stub
        if !original.isEmpty {
            return original.prefix(1).uppercased() + original.dropFirst() + " — refined."
        }
        return "Refined text would appear here."
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

            // Visible typing speed for demo (adjust this number to taste)
            try? await Task.sleep(for: .milliseconds(48))
        }
    }
}

