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
        contentHeight = 0
        sessionState = FloatingBarSessionState(startsInAskMode: RefinePreferences.startMode == .ask)
        appliedRevisions = []
        conversation = []
        lastApplyUndo = nil

        applyTargetElement = captureCurrentFocusedElement()
        applyTargetPID = resolveTargetPID(from: applyTargetElement, fallback: snapshot.pid)
        applyStrategy = strategy(
            for: applyTargetElement, role: snapshot.role, appName: snapshot.appName)
        let selectedText = snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : ""
        fallbackReplacesExistingInput = selectedText.isEmpty && !snapshot.fullText.isEmpty
        logTarget(snapshot: snapshot)
        currentSnapshot = snapshot

        ensurePanelExists()
        guard let panel, let hosting = hostingView else { return }

        let view = AnyView(
            FloatingBarView(
                snapshot: snapshot,
                sessionState: sessionState,
                onRefine: { [weak self] prompt, intent in
                    self?.performRefine(context: prompt, snapshot: snapshot, intent: intent)
                },
                onStop: { [weak self] in self?.stopRefine() },
                onClose: { [weak self] in self?.hide() },
                onUndo: { [weak self] in self?.undoLastApply() },
                onContentHeightChange: { [weak self] height in
                    // Not from inside SwiftUI's layout pass.
                    DispatchQueue.main.async {
                        self?.contentHeightChanged(to: height)
                    }
                }
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

    /// The bar eases to a new height while the panel jumps to it. Growing, that is
    /// fine: the panel makes room and the bar eases into it. Shrinking, the panel
    /// would cut the bar off as it eased, so it waits for the bar to finish.
    func contentHeightChanged(to height: CGFloat) {
        heightChangeGeneration &+= 1
        let generation = heightChangeGeneration
        let shrinking = height < contentHeight

        guard shrinking else {
            contentHeight = height
            sizePanelToFitContent(recenter: false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.heightChangeGeneration == generation else { return }
            self.contentHeight = height
            self.sizePanelToFitContent(recenter: false)
        }
    }

    /// Resizes the panel to whatever height its SwiftUI content currently needs.
    ///
    /// - Parameter recenter: `true` on first show. On later updates the top edge is
    ///   pinned instead, so the bar grows downward rather than jumping under the
    ///   cursor when an error appears.
    func sizePanelToFitContent(recenter: Bool) {
        guard let panel, let hosting = hostingView else { return }

        hosting.layoutSubtreeIfNeeded()

        // The panel only ever grows past its base size. Until SwiftUI has measured
        // the new content there is no height yet, and the base size stands in.
        let base = baseContentSize
        let size = NSSize(
            width: base.width,
            height: max(base.height, ceil(contentHeight))
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
        // The window shadow traces the drawn shapes, which just changed.
        panel.invalidateShadow()
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
                    onRefine: { _, _ in },
                    onStop: {},
                    onClose: {},
                    onUndo: nil
                )))
        hosting.frame = contentRect
        // The panel is sized by hand from the height SwiftUI reports. Left to the
        // hosting view's constraints, AppKit grows the window from its bottom edge
        // first, jumping the bar up before it is moved back.
        hosting.sizingOptions = []

        newPanel.contentView = hosting

        self.panel = newPanel
        self.hostingView = hosting
    }

    /// The bar's resting size: the source strip over the composer row.
    /// `sizePanelToFitContent` grows past this when needed (a wrapped error message)
    /// but never below it.
    var baseContentSize: NSSize { NSSize(width: 500, height: 74) }

    func viewSize(for snapshot: FieldSnapshot) -> NSSize {
        baseContentSize
    }

}
