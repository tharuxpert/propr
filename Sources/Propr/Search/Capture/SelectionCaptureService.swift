import AppKit
@preconcurrency import ApplicationServices

enum SelectionCapturePolicy {
    case refinementContext
    case lookupSelection

    var allowsWholeFieldCopy: Bool { self == .refinementContext }
}

/// Reads a source app before either Propr panel takes focus. Lookup never uses
/// select-all: only an explicit selection may start an automatic search.
@MainActor
final class SelectionCaptureService {
    static let shared = SelectionCaptureService()

    struct PreClickSelection {
        let gestureID: UUID
        let pid: pid_t
        let text: String
        let bounds: CGRect?
        let point: CGPoint
        let time: TimeInterval

        @MainActor
        func matches(gestureID: UUID, pid: pid_t, now: TimeInterval) -> Bool {
            return self.gestureID == gestureID && self.pid == pid && now - time < 1
                && SelectionCaptureService.selectionBounds(bounds, contain: point)
        }
    }

    private var preClickSelection: PreClickSelection?
    private let detector = FocusedFieldDetector()

    func snapshotForCurrentFocus() -> FieldSnapshot? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            pid != 0, pid != getpid()
        else { return nil }

        if let snapshot = detector.snapshotOfFocusedElement(), snapshot.pid == pid {
            return snapshot
        }
        return FieldSnapshot(
            appName: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown App",
            pid: pid,
            fullText: "",
            selectedText: nil,
            role: nil
        )
    }

    func prepare(
        _ snapshot: FieldSnapshot,
        policy: SelectionCapturePolicy,
        allowKeyboardFallback: Bool
    ) async -> FieldSnapshot {
        guard snapshot.pid != 0, snapshot.pid != getpid(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid
        else { return snapshot }

        if snapshot.selectedText?.isEmpty == false { return snapshot }
        guard allowKeyboardFallback else { return snapshot }
        if let selection = await SourceAppKeyboard(pid: snapshot.pid).copySelectedText() {
            return FieldSnapshot(
                appName: snapshot.appName,
                pid: snapshot.pid,
                fullText: policy == .refinementContext ? snapshot.fullText : "",
                selectedText: selection,
                role: snapshot.role
            )
        }

        guard policy.allowsWholeFieldCopy,
            TerminalApps.allowsSelectAllCapture(appName: snapshot.appName),
            let fullText = await SourceAppKeyboard(pid: snapshot.pid).copyCurrentInput()
        else { return snapshot }

        return FieldSnapshot(
            appName: snapshot.appName,
            pid: snapshot.pid,
            fullText: fullText,
            selectedText: nil,
            role: snapshot.role
        )
    }

    /// Called synchronously before an active event tap forwards mouse-down.
    /// Each AX operation has a short timeout; no clipboard or network work runs here.
    func recordMouseDown(gestureID: UUID, pid: pid_t, at point: CGPoint) {
        preClickSelection = nil
        guard pid != 0, pid != getpid(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let selection = readAXSelection(pid: pid, timeout: 0.03)
        else { return }

        preClickSelection = PreClickSelection(
            gestureID: gestureID,
            pid: pid,
            text: selection.text,
            bounds: selection.bounds,
            point: point,
            time: ProcessInfo.processInfo.systemUptime
        )
    }

    func clearPreClickSelection() {
        preClickSelection = nil
    }

    /// Current selection wins: Force Click can select a new word. The pre-click
    /// selection is used only when the click collapsed that same selection.
    func lookupSelection(pid: pid_t, gestureID: UUID? = nil, at point: CGPoint? = nil) async -> String? {
        let previous = preClickSelection
        preClickSelection = nil
        guard pid != 0, pid != getpid(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        else { return nil }

        if let current = readAXSelection(pid: pid, timeout: 0.06) {
            if let point {
                // AX can keep reporting an old selection after a press elsewhere.
                // Never treat nonempty selected text alone as proof that it belongs
                // to the pointer, including when the app omits selection bounds.
                guard selection(current, contains: point, pid: pid) else {
                    return readAXWord(pid: pid, at: point)
                }
            }
            return current.text
        }

        if let copied = await SourceAppKeyboard(pid: pid).copySelectedText() {
            return copied
        }

        guard let gestureID,
            previous?.matches(
                gestureID: gestureID,
                pid: pid,
                now: ProcessInfo.processInfo.systemUptime) == true
        else {
            return point.flatMap { readAXWord(pid: pid, at: $0) }
        }
        return previous?.text
    }

    private struct AXSelection {
        let text: String
        let bounds: CGRect?
        let range: CFRange?
        let element: AXUIElement
    }

    private func selection(_ selection: AXSelection, contains point: CGPoint, pid: pid_t) -> Bool {
        if let bounds = selection.bounds {
            return Self.selectionBounds(bounds, contain: point)
        }
        guard let selectedRange = selection.range,
            let (element, characterRange) = hitTestedRange(pid: pid, at: point),
            CFEqual(element, selection.element),
            characterRange.location >= selectedRange.location,
            characterRange.location < selectedRange.location + selectedRange.length
        else { return false }
        return true
    }

    static func selectionBounds(_ bounds: CGRect?, contain appKitPoint: CGPoint) -> Bool {
        guard let bounds else { return false }
        let quartzPoint = quartzPoint(from: appKitPoint)
        return bounds.insetBy(dx: -4, dy: -4).contains(quartzPoint)
    }

    private static func quartzPoint(from appKitPoint: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return appKitPoint }
        return CGPoint(x: appKitPoint.x, y: primary.frame.maxY - appKitPoint.y)
    }

    private static let wordPattern = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{N}_]+(?:['’.-][\\p{L}\\p{N}_]+)*"
    )

    static func word(in text: String, atUTF16Offset offset: Int) -> String? {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard offset >= 0, offset < fullRange.length else { return nil }
        guard let match = wordPattern.matches(in: text, range: fullRange).first(where: {
            NSLocationInRange(offset, $0.range)
        }) else { return nil }
        return (text as NSString).substring(with: match.range)
    }

    /// Pointer fallback for an unselected Force Click in an AX-capable app.
    /// The hit-tested element and character range both come from the click point;
    /// no document-wide text is used as a query.
    private func readAXWord(pid: pid_t, at appKitPoint: CGPoint) -> String? {
        guard let (element, range) = hitTestedRange(pid: pid, at: appKitPoint) else { return nil }

        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &valueRef) == .success,
            let value = valueRef as? String, value.count <= 8_000
        else { return nil }
        return Self.word(in: value, atUTF16Offset: range.location)
    }

    private func hitTestedRange(pid: pid_t, at appKitPoint: CGPoint)
        -> (AXUIElement, CFRange)?
    {
        let app = AXUIElementCreateApplication(pid)
        let timeout: Float = 0.06
        guard AXUIElementSetMessagingTimeout(app, timeout) == .success else { return nil }

        let point = Self.quartzPoint(from: appKitPoint)
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            app, Float(point.x), Float(point.y), &elementRef) == .success,
            let element = elementRef,
            AXUIElementSetMessagingTimeout(element, timeout) == .success
        else { return nil }

        var axPoint = point
        guard let parameter = AXValueCreate(.cgPoint, &axPoint) else { return nil }
        var rangeRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            parameter,
            &rangeRef) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }

        let rangeValue = unsafeDowncast(rangeRef, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange,
            AXValueGetValue(rangeValue, .cfRange, &range)
        else { return nil }
        return (element, range)
    }

    private func readAXSelection(pid: pid_t, timeout: Float) -> AXSelection? {
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, timeout) == .success else { return nil }

        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let focused = unsafeDowncast(focusedRef, to: AXUIElement.self)
        guard AXUIElementSetMessagingTimeout(focused, timeout) == .success else { return nil }

        var selectedRef: AnyObject?
        let directText: String?
        if AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success
        {
            directText = selectedRef as? String
        } else {
            directText = nil
        }

        var rangeRef: AnyObject?
        var selectionRange: CFRange?
        if AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        {
            let value = unsafeDowncast(rangeRef, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
                range.length > 0
            {
                selectionRange = range
            }
        }

        var text = directText
        if text?.isEmpty != false, let selectionRange {
            var valueRef: AnyObject?
            if AXUIElementCopyAttributeValue(
                focused, kAXValueAttribute as CFString, &valueRef) == .success,
                let value = valueRef as? String, value.count <= 8_000
            {
                let range = NSRange(location: selectionRange.location, length: selectionRange.length)
                let nsValue = value as NSString
                if NSMaxRange(range) <= nsValue.length {
                    text = nsValue.substring(with: range)
                }
            }
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count <= 8_000
        else { return nil }

        var bounds: CGRect?
        if var range = selectionRange,
            let parameter = AXValueCreate(.cfRange, &range)
        {
            var boundsRef: AnyObject?
            if AXUIElementCopyParameterizedAttributeValue(
                focused,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                parameter,
                &boundsRef) == .success,
                let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
            {
                let value = unsafeDowncast(boundsRef, to: AXValue.self)
                var rect = CGRect.zero
                if AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect) {
                    bounds = rect
                }
            }
        }
        return AXSelection(text: text, bounds: bounds, range: selectionRange, element: focused)
    }
}
