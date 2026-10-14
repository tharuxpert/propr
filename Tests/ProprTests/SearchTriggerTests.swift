import AppKit
import Testing

@testable import Propr

@MainActor
struct SearchTriggerTests {
    @Test("Fn fires on one short release, and duplicate monitors do not fire twice")
    func fnShortTap() {
        let detector = FnTapDetector()
        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function], at: 10))
        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function], at: 10))
        #expect(detector.flagsChanged(keyCode: 63, flags: [], at: 10.1))
        #expect(!detector.flagsChanged(keyCode: 63, flags: [], at: 10.1))
    }

    @Test("Fn rejects long holds and modifier chords")
    func fnHoldAndChords() {
        let detector = FnTapDetector()
        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function], at: 0))
        #expect(!detector.flagsChanged(keyCode: 63, flags: [], at: 0.31))

        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function], at: 1))
        #expect(!detector.flagsChanged(keyCode: 56, flags: [.function, .shift], at: 1.01))
        #expect(!detector.flagsChanged(keyCode: 63, flags: [], at: 1.1))

        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function, .command], at: 2))
        #expect(!detector.flagsChanged(keyCode: 63, flags: [], at: 2.1))
    }

    @Test("Fn plus a function key is not a standalone Fn tap")
    func fnFunctionKey() {
        let detector = FnTapDetector()
        #expect(!detector.flagsChanged(keyCode: 63, flags: [.function], at: 0))
        detector.keyDown()
        #expect(!detector.flagsChanged(keyCode: 63, flags: [], at: 0.1))
    }

    @Test("Ordinary clicks and stage-one pressure never trigger lookup")
    func ordinaryMousePress() {
        let detector = ForceClickPressDetector()
        let id = detector.mouseDown(at: .zero, pid: 123)
        #expect(id != nil)
        #expect(!detector.pressureChanged(to: 1, at: .zero).shouldSuppressNativeLookup)
        detector.mouseUp()
        #expect(!detector.pressureChanged(to: 2, at: .zero).shouldSuppressNativeLookup)
    }

    @Test("Only stage two accepts once for each press")
    func forceClickAcceptsOnce() {
        let detector = ForceClickPressDetector()
        let id = detector.mouseDown(at: CGPoint(x: 20, y: 30), pid: 456)
        let first = detector.pressureChanged(to: 2, at: CGPoint(x: 21, y: 30))
        guard case .newlyAccepted(let press) = first else {
            Issue.record("Stage two did not accept the press")
            return
        }
        #expect(press.id == id)
        #expect(press.pid == 456)
        #expect(press.point == CGPoint(x: 21, y: 30))
        #expect(detector.pressureChanged(to: 2, at: .zero).shouldSuppressNativeLookup)
        #expect(detector.pressureChanged(to: 1, at: .zero).shouldSuppressNativeLookup == false)
        if case .alreadyAccepted = detector.pressureChanged(to: 2, at: .zero) {
            // Duplicate pressure envelopes are suppressed, but no second lookup.
        } else {
            Issue.record("A second pressure envelope must not trigger a new lookup")
        }
    }

    @Test("Active and passive mouse-down share the original gesture")
    func activePassiveDedupe() {
        let detector = ForceClickPressDetector()
        let original = detector.mouseDown(at: .zero, pid: 111)
        #expect(detector.mouseDown(at: .zero, pid: 222, passive: true) == nil)
        guard case .newlyAccepted(let accepted) = detector.pressureChanged(to: 2, at: .zero) else {
            Issue.record("Expected stage-two acceptance")
            return
        }
        #expect(accepted.id == original)
        #expect(accepted.pid == 111)
    }

    @Test("Drag beyond four points rejects the entire press")
    func dragRejectsPress() {
        let detector = ForceClickPressDetector()
        _ = detector.mouseDown(at: .zero, pid: 1)
        detector.mouseDragged(to: CGPoint(x: 5, y: 0))
        detector.mouseDragged(to: .zero)
        #expect(!detector.pressureChanged(to: 2, at: .zero).shouldSuppressNativeLookup)

        detector.mouseUp()
        _ = detector.mouseDown(at: .zero, pid: 1)
        #expect(!detector.pressureChanged(to: 2, at: CGPoint(x: 0, y: 5)).shouldSuppressNativeLookup)
    }

    @Test("Quartz gesture and direct pressure envelopes are both decoded")
    func pressureEnvelopeRouting() async {
        // Both delivery paths are tapped: some systems report Force Click via
        // the gesture envelope (29), others via direct pressure (34).
        #expect(SearchTriggerService.eventMask & (1 << 29) != 0)
        #expect(SearchTriggerService.eventMask & (1 << 34) != 0)

        var stage = 1
        var decoded = 0
        var snapshots: [UUID] = []
        var lookups: [UUID] = []
        let service = SearchTriggerService(
            onFn: {},
            onMouseDown: { id, _, _ in snapshots.append(id) },
            onForceClick: { id, _, _ in lookups.append(id) },
            pressureReader: { _ in
                decoded += 1
                return (.pressure, stage)
            }
        )
        let event = CGEvent(source: nil)!
        service.mouseDown(at: .zero, pid: 123, passive: false)

        #expect(!service.handlePressureEnvelope(type: .leftMouseDragged, event: event, at: .zero))
        #expect(decoded == 0)
        #expect(!service.handlePressureEnvelope(type: SearchTriggerService.gestureEventType, event: event, at: .zero))
        stage = 2
        #expect(service.handlePressureEnvelope(type: SearchTriggerService.pressureEventType, event: event, at: .zero))
        #expect(service.handlePressureEnvelope(type: SearchTriggerService.gestureEventType, event: event, at: .zero))
        await Task.yield()
        #expect(snapshots.count == 1)
        #expect(lookups == snapshots)
    }

    @Test("Force Click switched off passes every event through and never looks up")
    func forceClickSwitchedOff() async {
        var snapshots = 0
        var lookups = 0
        let service = SearchTriggerService(
            onFn: {},
            onMouseDown: { _, _, _ in snapshots += 1 },
            onForceClick: { _, _, _ in lookups += 1 },
            pressureReader: { _ in (.pressure, 2) }
        )
        service.isForceClickEnabled = { false }
        let event = CGEvent(source: nil)!

        #expect(!service.handleActiveEvent(type: .leftMouseDown, event: event))
        #expect(!service.handleActiveEvent(type: SearchTriggerService.pressureEventType, event: event))
        await Task.yield()
        #expect(snapshots == 0)
        #expect(lookups == 0)

        // Back on, the same press is caught and native Look Up is suppressed.
        service.isForceClickEnabled = { true }
        _ = service.handleActiveEvent(type: .leftMouseDown, event: event)
        #expect(service.handleActiveEvent(type: SearchTriggerService.pressureEventType, event: event))
        await Task.yield()
        #expect(lookups == 1)
    }

    @Test("Fn switched off ignores a clean tap")
    func fnSwitchedOff() {
        var taps = 0
        let service = SearchTriggerService(onFn: { taps += 1 }, onMouseDown: { _, _, _ in }, onForceClick: { _, _, _ in })
        let fn = NSEvent.ModifierFlags.function.rawValue

        service.isFnEnabled = { false }
        service.processFnEvent(type: .flagsChanged, code: 63, flags: fn, time: 0)
        service.processFnEvent(type: .flagsChanged, code: 63, flags: 0, time: 0.1)
        #expect(taps == 0)

        service.isFnEnabled = { true }
        service.processFnEvent(type: .flagsChanged, code: 63, flags: fn, time: 1)
        service.processFnEvent(type: .flagsChanged, code: 63, flags: 0, time: 1.1)
        #expect(taps == 1)
    }

    @Test("Gesture envelopes without a press pass through untouched")
    func gestureFastPathWithoutPress() {
        var decoded = 0
        let service = SearchTriggerService(
            onFn: {},
            onMouseDown: { _, _, _ in },
            onForceClick: { _, _, _ in },
            pressureReader: { _ in
                decoded += 1
                return (.pressure, 2)
            }
        )
        let event = CGEvent(source: nil)!
        // No mouseDown: pinch/magnify has no button held, so the tap must
        // pass gesture envelopes through without AppKit decoding.
        #expect(!service.handleActiveEvent(type: SearchTriggerService.gestureEventType, event: event))
        #expect(decoded == 0)
        // With a press held (Force Click), the same envelope reaches decoding.
        // (Acceptance itself is drift-dependent on the live mouse position,
        // so this only asserts the fast path no longer skips the reader.)
        service.mouseDown(at: .zero, pid: 123, passive: false)
        _ = service.handleActiveEvent(type: SearchTriggerService.gestureEventType, event: event)
        #expect(decoded == 1)
    }

    @Test("Non-pressure gestures pass through")
    func nonPressureGesture() {
        var decoded = 0
        let service = SearchTriggerService(
            onFn: {},
            onMouseDown: { _, _, _ in },
            onForceClick: { _, _, _ in },
            pressureReader: { _ in
                decoded += 1
                return (.magnify, 2)
            }
        )
        let event = CGEvent(source: nil)!
        service.mouseDown(at: .zero, pid: 123, passive: false)
        // Gesture envelopes decoding to non-pressure pass through.
        #expect(!service.handlePressureEnvelope(type: SearchTriggerService.gestureEventType, event: event, at: .zero))
        #expect(decoded == 1)
        // Direct pressure events that decode to non-pressure also pass through.
        #expect(!service.handlePressureEnvelope(type: SearchTriggerService.pressureEventType, event: event, at: .zero))
        #expect(decoded == 2)
    }
}
