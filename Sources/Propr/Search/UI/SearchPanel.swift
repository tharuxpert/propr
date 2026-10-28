import AppKit

/// A search window that accepts keyboard input without taking over the source app.
final class SearchPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
