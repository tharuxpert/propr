import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Foundation

/// Lightweight snapshot of a focused text field we care about.
/// Does not hold the live AXUIElement (the detector and controller do that internally).
struct FieldSnapshot: Equatable {
    let appName: String
    let pid: pid_t
    let fullText: String
    let selectedText: String?
    let role: String?

    var characterCount: Int { fullText.count }
    var contextText: String { selectedText?.isEmpty == false ? selectedText! : fullText }

    /// Heuristic: is this worth showing the floating bar for?
    var isWorthShowing: Bool {
        // Ignore tiny/empty fields and our own windows. Selected text counts even if
        // the focused app does not expose a normal editable AX value.
        guard contextText.count > 2 else { return false }
        guard pid != getpid() else { return false }
        return true
    }
}

/// Reads focused text field snapshots via the Accessibility API.
///
/// Summon-only by design: focus is read when the user asks for the bar (double-tap
/// Command, or the menu item), never continuously. Propr deliberately does not run a
/// live AXObserver — a bar that appeared on every text field in every app would be
/// intrusive, and the system-wide focus notifications are unreliable across macOS
/// versions anyway.
///
/// All AX work stays on the main actor.
@MainActor
final class FocusedFieldDetector: ObservableObject {
    @Published private(set) var currentField: FieldSnapshot?

    private var systemWide: AXUIElement?
    private var lastSnapshot: FieldSnapshot?
    private var hideWorkItem: DispatchWorkItem?

    /// Clear any cached focus state.
    ///
    /// Propr reads focus only when the bar is explicitly summoned, so there is no
    /// observer to tear down here. This exists so callers can drop stale state when
    /// Accessibility permission goes away.
    func stop() {
        cancelPendingHide()
        systemWide = nil
        lastSnapshot = nil
        currentField = nil
    }

    /// Force an immediate re-evaluation of the currently focused element (useful for manual summon).
    func refreshCurrentFocus() {
        let sys = systemWide ?? AXUIElementCreateSystemWide()
        if systemWide == nil {
            systemWide = sys
        }

        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            sys, kAXFocusedUIElementAttribute as CFString, &focused)
        if result == .success, let axRef = focused, axElement(from: axRef) != nil {
            handleFocusChanged()
        }
    }

    // MARK: - Internal handling

    private func handleFocusChanged() {
        cancelPendingHide()

        let sys = systemWide ?? AXUIElementCreateSystemWide()
        if systemWide == nil {
            systemWide = sys
        }

        var focusedRef: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(
            sys, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard copyResult == .success, let axRef = focusedRef else {
            scheduleHide()
            return
        }

        guard let actualFocused = axElement(from: axRef) else {
            scheduleHide()
            return
        }

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

        let isEditableTextRole =
            role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String

        // Get owning app info
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown App"

        // Read value only for actual editable text controls. Container roles such as
        // AXWebArea/AXGroup/AXWindow can expose huge app context or terminal history,
        // which must not be treated as the user's input field. Some terminal apps
        // (notably Warp) also expose their transcript as an editable value, so we
        // sanitize suspiciously large or terminal-like values below.
        var valueRef: AnyObject?
        if isEditableTextRole {
            _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        }
        let rawFullText = (valueRef as? String) ?? ""

        // Selected range (optional but very useful)
        var selectedRange: NSRange?
        var selectedText: String?

        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let axRange = axValue(from: rangeRef),
            AXValueGetType(axRange) == .cfRange
        {
            var cfRange = CFRange()
            if AXValueGetValue(axRange, .cfRange, &cfRange) {
                selectedRange = NSRange(location: cfRange.location, length: cfRange.length)

                // Try to also grab the selected substring directly when available
                var selTextRef: AnyObject?
                if AXUIElementCopyAttributeValue(
                    element, kAXSelectedTextAttribute as CFString, &selTextRef) == .success,
                    let sel = selTextRef as? String, !sel.isEmpty
                {
                    selectedText = sel
                } else if let r = selectedRange, r.length > 0 {
                    let nsText = rawFullText as NSString
                    if NSMaxRange(r) <= nsText.length {
                        selectedText = nsText.substring(with: r)
                    }
                }
            }
        }

        let fullText =
            shouldTrustAXValue(rawFullText, appName: appName, role: role) ? rawFullText : ""

        let snapshot = FieldSnapshot(
            appName: appName,
            pid: pid,
            fullText: fullText,
            selectedText: selectedText,
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

    private func shouldTrustAXValue(_ value: String, appName: String, role: String?) -> Bool {
        guard !value.isEmpty else { return true }
        guard value.count <= 8_000 else { return false }
        guard !isTerminalLikeApp(appName) else { return false }
        return role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == "AXSearchFieldRole"
            || role == kAXComboBoxRole as String
    }

    private func isTerminalLikeApp(_ appName: String) -> Bool {
        let lowered = appName.lowercased()
        return lowered.contains("warp")
            || lowered.contains("terminal")
            || lowered.contains("iterm")
            || lowered.contains("ghostty")
            || lowered.contains("wezterm")
            || lowered.contains("alacritty")
            || lowered.contains("kitty")
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

    private func axElement(from ref: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    private func axValue(from ref: AnyObject?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(ref, to: AXValue.self)
    }

    deinit {
        // Cleanup is performed explicitly via stop() (always called from main actor).
        // Accessing CFRunLoopSource here would violate Swift 6 Sendable rules from nonisolated deinit.
    }
}
