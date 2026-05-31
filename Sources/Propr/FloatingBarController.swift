import SwiftUI
import AppKit
@preconcurrency import ApplicationServices
import Combine

/// Controls the floating refinement bar (NSPanel + SwiftUI content).
/// 
/// - Appears near a detected text field when the FocusedFieldDetector publishes a snapshot.
/// - Non-activating where possible so it doesn't steal focus from the source app.
/// - Captures the live AX element at show time for later "apply with typing" operations.
/// - All AX element mutation for apply happens here.
@MainActor
final class FloatingBarController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingBarView>?

    private weak var detector: FocusedFieldDetector?
    private var detectorObservation: AnyCancellable?

    /// The AX element we will write results back into. Captured when we first show the bar for a field.
    private var applyTargetElement: AXUIElement?

    /// Snapshot we showed for (used for positioning + UI state).
    private var currentSnapshot: FieldSnapshot?

    /// Whether the bar is currently visible.
    private(set) var isVisible: Bool = false

    init(detector: FocusedFieldDetector) {
        self.detector = detector
        setupObservation()
    }

    private func setupObservation() {
        // Observe detector changes on main and react.
        detectorObservation = detector?.$currentField
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                if let snapshot, snapshot.isWorthShowing {
                    print("[Propr Bar] Received focus snapshot for \(snapshot.appName) (len=\(snapshot.characterCount)) — showing bar")
                    self.show(for: snapshot)
                } else {
                    if let s = snapshot {
                        print("[Propr Bar] Snapshot for \(s.appName) not worth showing (len=\(s.characterCount), pid=\(s.pid)) — hiding")
                    } else {
                        print("[Propr Bar] No focused field (or focus lost) — hiding bar")
                    }
                    self.hide()
                }
            }
    }

    // MARK: - Public API

    /// Manually summon the bar for whatever is currently focused (bypasses the detector publish).
    func summonForCurrentFocus() {
        detector?.refreshCurrentFocus()
        // The observation will pick it up shortly; give it a nudge if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            if let snap = self?.detector?.currentField, snap.isWorthShowing {
                self?.show(for: snap)
            }
        }
    }

    /// Hide the floating bar and clear any captured target.
    func hide() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        isVisible = false
        // We intentionally keep the applyTarget for a short time in case of rapid hide/show,
        // but clear the snapshot.
        currentSnapshot = nil
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
        let view = FloatingBarView(
            snapshot: snapshot,
            onQuickAction: { [weak self] action in
                self?.handleQuickAction(action, snapshot: snapshot)
            },
            onRefine: { [weak self] customContext in
                self?.performRefine(context: customContext, snapshot: snapshot)
            },
            onClose: { [weak self] in
                self?.hide()
            }
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

    private func ensurePanelExists() {
        guard panel == nil else { return }

        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 140)

        let newPanel = NSPanel(
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

        // We rely on .nonactivatingPanel style + not calling makeKeyAndOrderFront in ways that activate us.
        // canBecomeKey is get-only on NSWindow in this SDK; the style mask is the correct signal.

        let hosting = NSHostingView(rootView: FloatingBarView(
            snapshot: FieldSnapshot(appName: "—", pid: 0, fullText: "", selectedText: nil, frame: .zero, role: nil),
            onQuickAction: { _ in },
            onRefine: { _ in },
            onClose: {}
        ))
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
            // Nothing to apply into anymore
            hide()
            return
        }

        let resultText = generateResult(from: snapshot, context: context)

        Task { @MainActor in
            await applyWithTypingAnimation(result: resultText, into: element)
            // After successful apply, hide the bar (user can re-focus to bring it back)
            try? await Task.sleep(for: .milliseconds(420))
            hide()
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

    private func applyWithTypingAnimation(result: String, into element: AXUIElement) async {
        // Strategy for refinement:
        // 1. Try to select the original selected range (or whole value if none).
        // 2. Progressively replace via kAXSelectedTextAttribute for a nice typing feel.

        // First, attempt to restore a reasonable selection range if we have one from capture time.
        // For simplicity in v1 we just set caret to end of current content and insert/overwrite.

        // Read current value length to place caret at end (common refinement pattern)
        var currentValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
           let text = currentValue as? String {
            let len = (text as NSString).length
            var range = CFRange(location: len, length: 0)
            if let rangeVal = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeVal)
            }
        }

        // Now "type" the result progressively.
        // Using small chunks feels smoother than 1 char at very high speed.
        let chunkSize = 2
        var index = result.startIndex

        while index < result.endIndex {
            let end = result.index(index, offsetBy: chunkSize, limitedBy: result.endIndex) ?? result.endIndex
            let chunk = String(result[index..<end])

            let status = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                chunk as CFString
            )

            if status != .success {
                // Fallback: try full value replace for this chunk (some fields only support value)
                // For demo we just continue; real impl could fall back harder.
            }

            // Natural typing cadence
            try? await Task.sleep(for: .milliseconds(28))

            index = end
        }
    }
}

