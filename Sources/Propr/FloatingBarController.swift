import AppKit
@preconcurrency import ApplicationServices
import Combine
import SwiftUI
enum TextApplyStrategy: Equatable {
    case accessibility
    case clipboardPaste
}

/// How to reverse an apply.
///
/// Replaces three loose properties that encoded two modes by convention ("the element
/// is nil but the pid is not" meant "send ⌘Z"), which would not have survived a third.
enum ApplyUndo {
    /// Put a field back through Accessibility, exactly as it was before the apply.
    case restoreField(element: AXUIElement, before: AXTextWriter.FieldState)
    /// Reverse typed keystrokes in the given process, by ⌘Z or by Backspace.
    case keystrokes(pid: pid_t, KeystrokeUndo, cursorTrailingCharacters: Int)
    /// Replace the current fallback result with the previous session result.
    case restorePreviousKeystrokes(
        pid: pid_t,
        removeCurrent: KeystrokeUndo,
        currentCursorTrailingCharacters: Int,
        previousText: String,
        previousCursorTrailingCharacters: Int,
        replacingExistingInput: Bool,
        appName: String
    )
}

struct AppliedRevision {
    let turn: RefinementTurn
    let undo: ApplyUndo
    /// Exact UTF-16 range occupied by this result in an AX-backed field.
    let accessibilityRange: CFRange?
    /// Caret position within `turn.output`, or nil to leave it at the end.
    let cursorUTF16Offset: Int?

    var cursorTrailingCharacterCount: Int {
        CursorMarkedText(text: turn.output, cursorUTF16Offset: cursorUTF16Offset)
            .trailingCharacterCount
    }
}

enum TextApplyError: LocalizedError {
    case cannotWriteAX
    case cannotPaste
    case sourceChanged
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .cannotWriteAX:
            return "Could not update the focused text field directly."
        case .cannotPaste:
            return "Could not paste or type the generated text into the source app."
        case .sourceChanged:
            return "The source text changed after Propr wrote it. Start a new session to avoid replacing the wrong text."
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
    var panel: FloatingPanel?
    var hostingView: FloatingPanelHostingView?

    var sessionState = FloatingBarSessionState()
    var refineTask: Task<Void, Never>?

    /// Incremented per refine request so a superseded task cannot publish its result.
    var refineGeneration = 0

    /// Keeps the panel sized to its content. The bar grows when a wrapped error
    /// message appears, which a fixed panel height would otherwise clip.
    var sessionStateCancellable: AnyCancellable?

    /// The AX element we will write results back into. Captured when we first show the bar for a field.
    var applyTargetElement: AXUIElement?
    var applyTargetPID: pid_t = 0
    var applyStrategy: TextApplyStrategy = .clipboardPaste

    /// Snapshot the bar is currently showing for (drives the header + preview).
    var currentSnapshot: FieldSnapshot?

    /// How to reverse an incomplete streamed apply, or the latest completed apply.
    var lastApplyUndo: ApplyUndo?

    /// Completed turns in this summon. This is both the model's chat history and the
    /// document revision stack used by turn-by-turn Undo.
    var appliedRevisions: [AppliedRevision] = []

    /// Whether fallback writes replace the original whole field. Follow-ups unwind
    /// to that same base state before inserting their next complete revision.
    var fallbackReplacesExistingInput = false

    // Used to force SwiftUI view recreation on every summon (resets @State)
    var summonID = UUID()

    /// Whether the bar is currently visible.
    /// Settable within the module because the presentation extension lives in
    /// another file, and Swift scopes `private(set)` to the declaring file.
    var isVisible: Bool = false

    init() {}

    /// The source target captured before the floating panel took keyboard focus.
    ///
    /// Do not try to recover a missing AX element here: once the panel is open, the
    /// focused element belongs to Propr and recapturing it replaces the real source
    /// PID with our own. Apps whose editors expose no AX element (including ChatGPT)
    /// must keep using the frontmost-app PID resolved at summon time.
    func capturedTargetForApply() -> (
        element: AXUIElement?, pid: pid_t, strategy: TextApplyStrategy
    ) {
        let element = applyTargetElement
        return (
            element: element,
            pid: applyTargetPID,
            strategy: element == nil ? .clipboardPaste : applyStrategy
        )
    }

    // MARK: - Public API

    /// Summon the floating bar (centered on screen). Captures the currently focused text field.
    func summon() {
        // The short delay is unchanged from before: it lets a status-bar menu that was
        // just clicked finish closing, so the focus read below is the user's field and
        // not the menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }

            Task { @MainActor in
                // Read the focused field now. This used to come from a cache updated on
                // timers, which is how a summon could show the previous one's context.
                //
                // Capture happens before the panel becomes key: for fallback targets
                // such as terminals, the source app's selection can be gone after that.
                guard let snapshot = SelectionCaptureService.shared.snapshotForCurrentFocus()
                else { return }
                let element = self.captureCurrentFocusedElement()
                let fallback = self.strategy(
                    for: element, role: snapshot.role, appName: snapshot.appName) == .clipboardPaste
                let prepared = await SelectionCaptureService.shared.prepare(
                    snapshot, policy: .refinementContext, allowKeyboardFallback: fallback)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid
                else { return }
                self.showCentered(for: prepared)
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

        // Nothing to undo once the bar is dismissed.
        lastApplyUndo = nil
        appliedRevisions = []
        fallbackReplacesExistingInput = false
    }

}
