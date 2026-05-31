@preconcurrency import Foundation
@preconcurrency import ApplicationServices
import AppKit

/// Lightweight snapshot of a focused text field we care about.
/// Does not hold the live AXUIElement (the detector and controller do that internally).
struct FieldSnapshot: Equatable {
    let appName: String
    let pid: pid_t
    let fullText: String
    let selectedText: String?
    let frame: CGRect          // Screen coordinates (AppKit origin: top-left of main screen)
    let role: String?

    var characterCount: Int { fullText.count }

    /// Heuristic: is this worth showing the floating bar for?
    var isWorthShowing: Bool {
        // Ignore tiny/empty fields and our own windows
        guard characterCount > 2 else { return false }
        guard pid != getpid() else { return false }
        return true
    }
}

/// Manages system-wide observation of focused text fields via the Accessibility API.
/// Publishes a `currentField` snapshot whenever a qualifying text field gains focus.
///
/// All heavy AX work stays on the main actor. The C callback hops back via Unmanaged refcon.
@MainActor
final class FocusedFieldDetector: ObservableObject {
    @Published private(set) var currentField: FieldSnapshot?

    private var observer: AXObserver?
    private var systemWide: AXUIElement?
    private var runLoopSource: CFRunLoopSource?

    /// Fallback trigger using AppKit (very reliable even when AXObserverAddNotification fails on system-wide).
    private var appActivationObserver: NSObjectProtocol?

    private var lastSnapshot: FieldSnapshot?
    private var hideWorkItem: DispatchWorkItem?

    /// Start observing focused UI element changes across the system.
    /// Safe to call multiple times; does nothing if already running or permission is missing.
    func start() {
        guard AXIsProcessTrusted() else {
            print("[Propr Detector] start() called but AXIsProcessTrusted() == false — observer not created")
            return
        }
        guard observer == nil else { return }

        print("[Propr Detector] Permission OK — creating system-wide AXObserver for focused UI element changes")

        let sys = AXUIElementCreateSystemWide()
        self.systemWide = sys

        let callback: AXObserverCallbackWithInfo = { _, element, notification, info, refcon in
            guard let refcon else { return }
            let detector = Unmanaged<FocusedFieldDetector>.fromOpaque(refcon).takeUnretainedValue()

            // Hop to main actor for all subsequent work (Published updates + AX reads must be main)
            Task { @MainActor in
                detector.handleFocusChanged(element: element, notification: notification as String)
            }
        }

        var axObserver: AXObserver?
        let pid = getpid()
        let createResult = AXObserverCreateWithInfoCallback(pid, callback, &axObserver)

        guard createResult == .success, let created = axObserver else {
            print("[FocusedFieldDetector] Failed to create AXObserver: \(createResult.rawValue)")
            return
        }

        self.observer = created

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // We register for two notifications on the system-wide element:
        // 1. kAXFocusedApplicationChangedNotification — this one is reliable and fires when the user
        //    switches focus to a different app. This is our main trigger.
        // 2. kAXFocusedUIElementChangedNotification — attempted for direct text-field focus changes
        //    inside the same app. This often fails on modern macOS with kAXErrorInvalidUIElement (-25202)
        //    when added to the system-wide element, so we treat it as best-effort.
        var addedAnything = false

        let appChangedResult = AXObserverAddNotification(
            created,
            sys,
            kAXApplicationActivatedNotification as CFString,
            refcon
        )
        if appChangedResult == .success {
            addedAnything = true
        } else {
            print("[Propr Detector] Failed to add app-changed notification: \(appChangedResult.rawValue)")
        }

        let uiElementResult = AXObserverAddNotification(
            created,
            sys,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )
        if uiElementResult == .success {
            addedAnything = true
        } else {
            print("[Propr Detector] Could not add direct focused-UI notification (\(uiElementResult.rawValue)) — this is expected on many macOS versions; using application-activated + re-query instead.")
        }

        let source = AXObserverGetRunLoopSource(created)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        if addedAnything {
            print("[Propr Detector] AXObserver registered for some notifications.")
        } else {
            print("[Propr Detector] AXObserverAddNotification failed for both (common in some dev setups). Using AppKit fallback + direct queries.")
        }

        // Reliable AppKit-level fallback. This fires whenever any app becomes frontmost.
        // We use it to trigger a fresh AX query of the current focused UI element.
        // This works even when AXObserver notification registration completely fails on system-wide.
        if appActivationObserver == nil {
            appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Small delay gives the focused element time to settle after app switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    Task { @MainActor in
                        self?.refreshCurrentFocus()
                    }
                }
            }
            print("[Propr Detector] Registered NSWorkspace app-activation fallback (this should make auto-show reliable).")
        }

        // Always do an initial query
        refreshCurrentFocus()
    }

    /// Stop observing and clean up the run loop source.
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        if let token = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            appActivationObserver = nil
        }

        // We don't have a direct remove for all notifications in one shot; releasing is sufficient.
        observer = nil
        runLoopSource = nil
        systemWide = nil
        currentField = nil
    }

    /// Force an immediate re-evaluation of the currently focused element (useful for manual summon).
    func refreshCurrentFocus() {
        guard let sys = systemWide ?? AXUIElementCreateSystemWide() as AXUIElement? else { return }

        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused)
        if result == .success, let axRef = focused {
            // AXUIElement from AX API — unsafeDowncast is the recommended form here
            let element = unsafeDowncast(axRef, to: AXUIElement.self)
            handleFocusChanged(element: element, notification: "manual-refresh")
        }
    }

    // MARK: - Internal handling

    private func handleFocusChanged(element: AXUIElement, notification: String) {
        cancelPendingHide()

        // IMPORTANT:
        // The `element` passed here may be the *application* (when kAXFocusedApplicationChangedNotification fired)
        // or a UI element (when the direct focused-UI notification fired on systems where it works).
        // The only reliable thing is to freshly read the actual focused UI element right now.
        guard let sys = systemWide else { return }

        var focusedRef: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard copyResult == .success, let axRef = focusedRef else {
            scheduleHide()
            return
        }

        let actualFocused = unsafeDowncast(axRef, to: AXUIElement.self)

        // Small debounce to ignore rapid focus dance inside the same app (e.g. label -> field)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.evaluateAndPublish(element: actualFocused)
            }
        }
    }

    private func evaluateAndPublish(element: AXUIElement) {
        // Read role first — fast filter
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        _ = role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String
            || role == "AXWebArea" // Some web views expose this; we'll still try value

        // Get owning app info
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown App"

        // Read value (this is the main content for most fields)
        var valueRef: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let fullText = (valueRef as? String) ?? ""

        // Selected range (optional but very useful)
        var selectedRange: NSRange?
        var selectedText: String?

        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let axRange = rangeRef as! AXValue?,
           AXValueGetType(axRange) == .cfRange {
            var cfRange = CFRange()
            if AXValueGetValue(axRange, .cfRange, &cfRange) {
                selectedRange = NSRange(location: cfRange.location, length: cfRange.length)

                // Try to also grab the selected substring directly when available
                var selTextRef: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selTextRef) == .success,
                   let sel = selTextRef as? String, !sel.isEmpty {
                    selectedText = sel
                } else if let r = selectedRange, r.length > 0, r.location + r.length <= fullText.count {
                    let start = fullText.index(fullText.startIndex, offsetBy: r.location)
                    let end = fullText.index(start, offsetBy: r.length)
                    selectedText = String(fullText[start..<end])
                }
            }
        }

        // Read frame (position + size) and convert AX coords (bottom-left origin) to AppKit (top-left)
        let frame = readFrame(for: element)

        let snapshot = FieldSnapshot(
            appName: appName,
            pid: pid,
            fullText: fullText,
            selectedText: selectedText,
            frame: frame,
            role: role
        )

        // Only publish if meaningfully different or first time
        if snapshot.isWorthShowing && snapshot != lastSnapshot {
            lastSnapshot = snapshot
            currentField = snapshot
        } else if !snapshot.isWorthShowing {
            // If we landed on something uninteresting (e.g. a button), hide after a tiny grace period
            scheduleHide()
        }
    }

    private func readFrame(for element: AXUIElement) -> CGRect {
        var posRef: AnyObject?
        var sizeRef: AnyObject?

        var origin = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           let axPos = posRef as! AXValue?,
           AXValueGetType(axPos) == .cgPoint {
            AXValueGetValue(axPos, .cgPoint, &origin)
        }

        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let axSize = sizeRef as! AXValue?,
           AXValueGetType(axSize) == .cgSize {
            AXValueGetValue(axSize, .cgSize, &size)
        }

        // Convert from AX coordinate space (bottom-left origin on main screen) to AppKit (top-left)
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            let flippedY = screenHeight - origin.y - size.height
            return CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)
        }

        return CGRect(origin: origin, size: size)
    }

    private func scheduleHide() {
        cancelPendingHide()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.currentField = nil
                self?.lastSnapshot = nil
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelPendingHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    deinit {
        // Cleanup is performed explicitly via stop() (always called from main actor).
        // Accessing CFRunLoopSource here would violate Swift 6 Sendable rules from nonisolated deinit.
    }
}
