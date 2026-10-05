import CoreGraphics
import Foundation

/// One gesture state machine shared by the active tap and passive monitor.
/// Coordinates are AppKit global screen points at this boundary.
@MainActor
final class ForceClickPressDetector {
    enum PressureDecision {
        case rejected
        case newlyAccepted(AcceptedPress)
        case alreadyAccepted

        var shouldSuppressNativeLookup: Bool {
            switch self {
            case .rejected: false
            case .newlyAccepted, .alreadyAccepted: true
            }
        }
    }

    struct AcceptedPress {
        let id: UUID
        let pid: pid_t
        let point: CGPoint
    }

    private struct Press {
        let id: UUID
        let pid: pid_t
        let origin: CGPoint
        var exceededDrift = false
        var fired = false
    }

    private var press: Press?
    private var stage = 0

    /// Whether a button press is currently tracked. The event-tap callback
    /// uses this as a fast path: trackpad pinch/magnify never holds a mouse
    /// button, so gesture envelopes with no active press pass through without
    /// AppKit decoding or screen-coordinate lookups.
    var hasActivePress: Bool { press != nil }

    func mouseDown(at point: CGPoint, pid: pid_t, passive: Bool = false) -> UUID? {
        // Passive delivery follows the original click and must preserve the
        // earlier, pre-click selection snapshot and its gesture ID.
        if passive, press != nil { return nil }
        let id = UUID()
        press = Press(id: id, pid: pid, origin: point)
        stage = 0
        return id
    }

    func mouseDragged(to point: CGPoint) {
        guard var current = press else { return }
        if Self.exceedsDrift(from: current.origin, to: point) {
            current.exceededDrift = true
            press = current
        }
    }

    func pressureChanged(to newStage: Int, at point: CGPoint) -> PressureDecision {
        let enteredStageTwo = stage < 2 && newStage == 2
        stage = newStage
        guard newStage == 2, var current = press else { return .rejected }
        if current.fired { return .alreadyAccepted }
        guard enteredStageTwo else { return .rejected }
        if current.exceededDrift || Self.exceedsDrift(from: current.origin, to: point) {
            current.exceededDrift = true
            press = current
            return .rejected
        }
        current.fired = true
        press = current
        return .newlyAccepted(AcceptedPress(id: current.id, pid: current.pid, point: point))
    }

    func mouseUp() {
        press = nil
        stage = 0
    }

    func cancel() { mouseUp() }

    private static func exceedsDrift(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return dx * dx + dy * dy > 16 // Four screen points.
    }
}
