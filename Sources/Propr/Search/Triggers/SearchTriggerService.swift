import AppKit
import CoreGraphics

/// Fn and trackpad Force Click entry points for the read-only search panel.
/// The active tap is installed on the main run loop. Its mouse-down callback is
/// synchronous so callers can snapshot AX selection before forwarding the click.
@MainActor
final class SearchTriggerService {
    private typealias PressureReader = (CGEvent) -> (type: NSEvent.EventType, stage: Int)?

    // Quartz delivers Force Click pressure as a generic-gesture envelope (29)
    // on some systems and as the direct AppKit pressure type (34) on others,
    // so both are tapped. Type 29 also carries the trackpad gesture stream
    // (pinch/magnify, swipe, rotate): those events pass through untouched via
    // the no-press fast path in handleActiveEvent, since gestures never hold
    // a mouse button.
    static let gestureEventType = CGEventType(rawValue: 29)!
    static let pressureEventType = CGEventType(rawValue: 34)!
    static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << gestureEventType.rawValue)
        | (1 << pressureEventType.rawValue)

    private static weak var activeService: SearchTriggerService?

    private let onFn: @MainActor () -> Void
    private let onMouseDown: @MainActor (UUID, pid_t, CGPoint) -> Void
    private let onForceClick: @MainActor (UUID, pid_t, CGPoint) -> Void
    private let pressureReader: PressureReader

    /// Whether each trigger is switched on, asked at the moment of the gesture.
    /// Injected rather than read from settings here, so tests do not depend on the
    /// user's saved preferences.
    var isFnEnabled: @MainActor () -> Bool = { true }
    var isForceClickEnabled: @MainActor () -> Bool = { true }

    private var fnDetector = FnTapDetector()
    private var forceDetector = ForceClickPressDetector()
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?
    private var passiveMouseMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    init(
        onFn: @escaping @MainActor () -> Void,
        onMouseDown: @escaping @MainActor (UUID, pid_t, CGPoint) -> Void,
        onForceClick: @escaping @MainActor (UUID, pid_t, CGPoint) -> Void
    ) {
        self.onFn = onFn
        self.onMouseDown = onMouseDown
        self.onForceClick = onForceClick
        pressureReader = Self.decodePressure
    }

    // The reader injection lets tests exercise Quartz-envelope routing without
    // requiring a physical Force Touch trackpad.
    init(
        onFn: @escaping @MainActor () -> Void,
        onMouseDown: @escaping @MainActor (UUID, pid_t, CGPoint) -> Void,
        onForceClick: @escaping @MainActor (UUID, pid_t, CGPoint) -> Void,
        pressureReader: @escaping (CGEvent) -> (type: NSEvent.EventType, stage: Int)?
    ) {
        self.onFn = onFn
        self.onMouseDown = onMouseDown
        self.onForceClick = onForceClick
        self.pressureReader = pressureReader
    }

    func start() {
        guard Self.activeService == nil else { return }
        Self.activeService = self

        let fnMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        fnGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: fnMask,
            handler: Self.handleFnEvent
        )
        fnLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: fnMask,
            handler: Self.handleLocalFnEvent
        )

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: searchTriggerEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventTapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        // The passive monitor is a safety net for a denied or silent CG tap.
        // It cannot suppress the native Look Up action.
        passiveMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.pressure, .leftMouseDown, .leftMouseUp],
            handler: Self.handlePassiveMouseEvent
        )
    }

    func stop() {
        if let monitor = fnGlobalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = fnLocalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = passiveMouseMonitor { NSEvent.removeMonitor(monitor) }
        fnGlobalMonitor = nil
        fnLocalMonitor = nil
        passiveMouseMonitor = nil

        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        eventTapSource = nil
        fnDetector.reset()
        forceDetector.cancel()
        if Self.activeService === self { Self.activeService = nil }
    }

    // MARK: - Event monitor callbacks

    /// Do not pass NSEvent across actors. These static entry points avoid the
    /// inherited @MainActor runtime assertion seen with inline event closures.
    nonisolated private static func handleFnEvent(_ event: NSEvent) {
        let type = event.type
        let code = event.keyCode
        let flags = event.modifierFlags.rawValue
        let time = event.timestamp
        Task { @MainActor in
            Self.activeService?.processFnEvent(type: type, code: code, flags: flags, time: time)
        }
    }

    nonisolated private static func handleLocalFnEvent(_ event: NSEvent) -> NSEvent? {
        handleFnEvent(event)
        return event
    }

    /// Internal for test coverage of the Fn on/off switch.
    func processFnEvent(type: NSEvent.EventType, code: UInt16, flags: UInt, time: TimeInterval) {
        switch type {
        case .keyDown:
            fnDetector.keyDown()
        case .flagsChanged:
            if fnDetector.flagsChanged(
                keyCode: code,
                flags: NSEvent.ModifierFlags(rawValue: flags),
                at: time
            ), isFnEnabled() {
                onFn()
            }
        default:
            break
        }
    }

    nonisolated private static func handlePassiveMouseEvent(_ event: NSEvent) {
        let type = event.type
        let stage = event.type == .pressure ? event.stage : 0
        let quartzPoint = event.cgEvent?.location
        let targetPID = event.cgEvent.map { Int32($0.getIntegerValueField(.eventTargetUnixProcessID)) }
        Task { @MainActor in
            guard let service = Self.activeService, service.isForceClickEnabled() else { return }
            let point = quartzPoint.map(Self.appKitPoint) ?? NSEvent.mouseLocation
            let pid = service.sourcePID(targetPID)
            switch type {
            case .leftMouseDown:
                service.mouseDown(at: point, pid: pid, passive: true)
            case .leftMouseUp:
                service.forceDetector.mouseUp()
            case .pressure:
                service.acceptPressure(stage: stage, at: point)
            default:
                break
            }
        }
    }

    /// Called synchronously by the tap callback before the original event is
    /// forwarded. Only accepted stage-two pressure returns true for suppression.
    /// Point conversion (NSScreen lookup) and AppKit decoding are deferred past
    /// the gesture fast path so the high-frequency pinch stream passes through
    /// with minimal work when no button is held.
    /// Internal for test coverage of the gesture fast path.
    func handleActiveEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            forceDetector.cancel()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        case _ where !isForceClickEnabled():
            // Switched off: every event passes through untouched, so the system's
            // own Force Click Look Up works again.
            forceDetector.cancel()
            return false
        case .leftMouseDown:
            mouseDown(
                at: Self.appKitPoint(event.location),
                pid: sourcePID(Int32(event.getIntegerValueField(.eventTargetUnixProcessID))),
                passive: false
            )
        case .leftMouseDragged:
            forceDetector.mouseDragged(to: Self.appKitPoint(event.location))
        case .leftMouseUp:
            forceDetector.mouseUp()
        default:
            if type == Self.gestureEventType, !forceDetector.hasActivePress {
                return false
            }
            return handlePressureEnvelope(
                type: type, event: event, at: Self.appKitPoint(event.location))
        }
        return false
    }

    func mouseDown(at point: CGPoint, pid: pid_t, passive: Bool) {
        guard let id = forceDetector.mouseDown(at: point, pid: pid, passive: passive) else { return }
        // In the active path this runs before CGEventTap forwards mouse-down.
        onMouseDown(id, pid, point)
    }

    @discardableResult
    func handlePressureEnvelope(type: CGEventType, event: CGEvent, at point: CGPoint) -> Bool {
        // Both the generic gesture envelope (29) and direct pressure (34) can
        // carry Force Click pressure; only .pressure decodings act. Anything
        // else (magnify/swipe/rotate) passes through. The no-press fast path
        // in handleActiveEvent keeps the pinch stream from reaching decoding
        // at all during button-free gestures.
        guard type == Self.gestureEventType || type == Self.pressureEventType,
              let decoded = pressureReader(event), decoded.type == .pressure else { return false }
        return acceptPressure(stage: decoded.stage, at: point)
    }

    @discardableResult
    private func acceptPressure(stage: Int, at point: CGPoint) -> Bool {
        let decision = forceDetector.pressureChanged(to: stage, at: point)
        if case .newlyAccepted(let accepted) = decision {
            // Opening the panel must not extend the event-tap callback duration.
            Task { @MainActor in
                onForceClick(accepted.id, accepted.pid, accepted.point)
            }
        }
        return decision.shouldSuppressNativeLookup
    }

    private func sourcePID(_ eventPID: pid_t?) -> pid_t {
        if let eventPID, eventPID > 0 { return eventPID }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    private static func decodePressure(_ event: CGEvent) -> (type: NSEvent.EventType, stage: Int)? {
        guard let converted = NSEvent(cgEvent: event) else { return nil }
        return (converted.type, converted.stage)
    }

    /// Quartz points have a top-left origin; lookup capture and panel positioning
    /// use AppKit's bottom-left global screen coordinate system.
    private static func appKitPoint(_ point: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
    }
}

/// The callback is nonisolated; its run-loop source is always attached to the
/// main run loop in start(), so this synchronous actor hop is valid.
private struct MainRunLoopEvent: @unchecked Sendable {
    // Never retained or sent to another thread. The tap is installed on the
    // main run loop and this wrapper exists only for the synchronous actor hop.
    let value: CGEvent
}

private func searchTriggerEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<SearchTriggerService>.fromOpaque(userInfo).takeUnretainedValue()
    let mainRunLoopEvent = MainRunLoopEvent(value: event)
    let accepted = MainActor.assumeIsolated {
        service.handleActiveEvent(type: type, event: mainRunLoopEvent.value)
    }
    return accepted ? nil : Unmanaged.passUnretained(event)
}
