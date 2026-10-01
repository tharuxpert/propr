import AppKit

/// A search window that accepts keyboard input without taking over the source app.
final class SearchPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    private struct ResizeEdges: OptionSet {
        let rawValue: Int
        static let left = ResizeEdges(rawValue: 1)
        static let right = ResizeEdges(rawValue: 2)
        static let bottom = ResizeEdges(rawValue: 4)
        static let top = ResizeEdges(rawValue: 8)
    }

    private let edgeWidth: CGFloat = 7
    private var activeEdges: ResizeEdges = []
    private var dragStartFrame: NSRect = .zero
    private var dragStartPoint: NSPoint = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            activeEdges = edges(at: event.locationInWindow)
            if !activeEdges.isEmpty {
                dragStartFrame = frame
                dragStartPoint = convertPoint(toScreen: event.locationInWindow)
                return
            }
        case .leftMouseDragged:
            if !activeEdges.isEmpty {
                resize(to: convertPoint(toScreen: event.locationInWindow))
                return
            }
        case .leftMouseUp:
            if !activeEdges.isEmpty {
                activeEdges = []
                return
            }
        case .mouseMoved:
            let hoverEdges = edges(at: event.locationInWindow)
            if hoverEdges.contains(.left) || hoverEdges.contains(.right) {
                NSCursor.resizeLeftRight.set()
            } else if hoverEdges.contains(.top) || hoverEdges.contains(.bottom) {
                NSCursor.resizeUpDown.set()
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func edges(at point: NSPoint) -> ResizeEdges {
        let bounds = NSRect(origin: .zero, size: frame.size)
        guard bounds.contains(point) else { return [] }
        var result: ResizeEdges = []
        if point.x < edgeWidth { result.insert(.left) }
        if point.x > bounds.maxX - edgeWidth { result.insert(.right) }
        if point.y < edgeWidth { result.insert(.bottom) }
        if point.y > bounds.maxY - edgeWidth { result.insert(.top) }
        return result
    }

    private func resize(to point: NSPoint) {
        let dx = point.x - dragStartPoint.x
        let dy = point.y - dragStartPoint.y
        var next = dragStartFrame

        if activeEdges.contains(.left) { next.size.width -= dx }
        if activeEdges.contains(.right) { next.size.width += dx }
        if activeEdges.contains(.bottom) { next.size.height -= dy }
        if activeEdges.contains(.top) { next.size.height += dy }

        next.size.width = min(max(next.width, minSize.width), maxSize.width)
        next.size.height = min(max(next.height, minSize.height), maxSize.height)
        if activeEdges.contains(.left) { next.origin.x = dragStartFrame.maxX - next.width }
        if activeEdges.contains(.bottom) { next.origin.y = dragStartFrame.maxY - next.height }
        setFrame(next, display: true)
    }
}
