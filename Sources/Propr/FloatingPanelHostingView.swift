import AppKit
import SwiftUI

/// The floating bar's hosting view, which claims the mouse while it is over the bar.
///
/// The bar lives in a non-activating panel, so Propr is never the active app. By
/// default that means the bar receives no hover events at all: the app that *is*
/// active keeps tracking the mouse, so a link behind the bar underlined and the
/// pointer turned into its hand while you were plainly hovering over Propr.
///
/// A tracking area with `.activeAlways` is the documented way to receive mouse
/// movement regardless of whether the app is active. It deliberately does not
/// include `.cursorUpdate`: AppKit's documentation states that cursor-update
/// messages are not sent when that option is combined with `.activeAlways`, which
/// is exactly Propr's situation. So the cursor is set by hand on every movement.
///
/// `acceptsMouseMovedEvents` on the window would also deliver movement, but it
/// floods every event to the whole window and is reported to break SwiftUI's
/// `onHover`, so it is avoided.
final class FloatingPanelHostingView: NSHostingView<AnyView> {
    private var pointerTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }

        // `.inVisibleRect` keeps the area matched to the view as the bar resizes,
        // so the rect passed here is ignored.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updatePointer(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updatePointer(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Hand the pointer back; whatever is under it now will set its own.
        NSCursor.arrow.set()
    }

    /// An I-beam over editable text, the arrow everywhere else — what the system
    /// would show if Propr were the active app.
    private func updatePointer(for event: NSEvent) {
        // hitTest(_:) expects a point in the superview's coordinate space.
        let point = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow

        let overText =
            sequence(first: hitTest(point), next: { $0?.superview })
            .contains { view in
                guard let view else { return false }
                if let field = view as? NSTextField { return field.isEditable }
                if let text = view as? NSTextView { return text.isEditable }
                return false
            }

        (overText ? NSCursor.iBeam : NSCursor.arrow).set()
    }
}
