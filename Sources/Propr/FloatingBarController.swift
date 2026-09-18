import AppKit
@preconcurrency import ApplicationServices
import Combine
import SwiftUI
enum TextApplyStrategy {
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
    case keystrokes(pid: pid_t, KeystrokeUndo)
}

enum TextApplyError: LocalizedError {
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
    var panel: FloatingPanel?
    var hostingView: FloatingPanelHostingView?

    /// Reads the focused field on demand; holds no state between summons.
    let detector = FocusedFieldDetector()
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

    /// How to reverse the last apply, or nil when there is nothing to undo.
    var lastApplyUndo: ApplyUndo?

    // Used to force SwiftUI view recreation on every summon (resets @State)
    var summonID = UUID()

    /// Whether the bar is currently visible.
    /// Settable within the module because the presentation extension lives in
    /// another file, and Swift scopes `private(set)` to the declaring file.
    var isVisible: Bool = false

    init() {}

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
                if let snapshot = self.detector.snapshotOfFocusedElement() {
                    // Show the real target even with no text to work on: the user asked
                    // for the bar, and an empty context is a valid way to use it.
                    let prepared = await self.prepareSnapshotForSummon(snapshot)
                    self.showCentered(for: prepared)
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

        // Nothing to undo once the bar is dismissed.
        lastApplyUndo = nil
    }

}
