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

    @Test("Non-pressure gestures pass through")
    func nonPressureGesture() {
        let service = SearchTriggerService(
            onFn: {},
            onMouseDown: { _, _, _ in },
            onForceClick: { _, _, _ in },
            pressureReader: { _ in (.magnify, 2) }
        )
        let event = CGEvent(source: nil)!
        service.mouseDown(at: .zero, pid: 123, passive: false)
        #expect(!service.handlePressureEnvelope(type: SearchTriggerService.gestureEventType, event: event, at: .zero))
    }
}
