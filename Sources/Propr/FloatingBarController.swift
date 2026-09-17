import AppKit
@preconcurrency import ApplicationServices
import Combine
import SwiftUI
enum TextApplyStrategy {
    case accessibility
    case clipboardPaste
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
    var hostingView: NSHostingView<AnyView>?

    weak var detector: FocusedFieldDetector?
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

    // Undo support
    var undoOriginalText: String?
    var undoElement: AXUIElement?
    var undoSourcePID: pid_t = 0

    // Used to force SwiftUI view recreation on every summon (resets @State)
    var summonID = UUID()

    /// Whether the bar is currently visible.
    /// Settable within the module because the presentation extension lives in
    /// another file, and Swift scopes `private(set)` to the declaring file.
    var isVisible: Bool = false

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
                    // Show the real target even with no text to work on: the user asked
                    // for the bar, and an empty context is a valid way to use it (ask
                    // for something to be written at the cursor). Falling back to the
                    // placeholder here would drop the app's name and icon.
                    let prepared = await self.prepareSnapshotForSummon(baseSnapshot)
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

        // Clear undo state when the bar is dismissed
        undoOriginalText = nil
        undoElement = nil
        undoSourcePID = 0
    }

}
