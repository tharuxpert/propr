import AppKit
import SwiftUI


/// Custom panel that can become key so SwiftUI TextFields inside can receive keyboard input.
/// We still keep nonactivatingPanel style so it doesn't steal activation from the original app aggressively.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}


// Presentation of the floating bar: building the panel, sizing it to its SwiftUI
// content and placing it on screen. Separated from the refine/apply logic, which is
// what the controller itself is about.
extension FloatingBarController {
    func showCentered(for snapshot: FieldSnapshot) {
        print("[Propr Bar] summon — showing centered for \(snapshot.appName)")

        // Fresh ID so SwiftUI recreates the view and resets all @State (prompt, hasApplied, etc.)
        summonID = UUID()
        sessionState = FloatingBarSessionState()

        applyTargetElement = captureCurrentFocusedElement()
        applyTargetPID = resolveTargetPID(from: applyTargetElement, fallback: snapshot.pid)
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

    func showCenteredEmpty() {
        summonID = UUID()
        sessionState = FloatingBarSessionState()

        // Resolve the target first: the snapshot is built from it, and without a real
        // pid the bar would open but be unable to write anything back.
        applyTargetElement = captureCurrentFocusedElement()
        applyTargetPID = resolveTargetPID(from: applyTargetElement, fallback: 0)

        // Name the app we resolved to, rather than showing a placeholder dash.
        let appName =
            NSRunningApplication(processIdentifier: applyTargetPID)?.localizedName ?? "—"
        let dummy = FieldSnapshot(
            appName: appName, pid: applyTargetPID, fullText: "", selectedText: nil, role: nil)

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
    func sizePanelToFitContent(recenter: Bool) {
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
    func observeSessionStateForResizing() {
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

    func centerPanel(size: NSSize) {
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

    func ensurePanelExists() {
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

        let hosting = FloatingPanelHostingView(
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
    var baseContentSize: NSSize { NSSize(width: 510, height: 196) }

    func viewSize(for snapshot: FieldSnapshot) -> NSSize {
        baseContentSize
    }

}
