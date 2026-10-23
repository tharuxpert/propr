import AppKit

/// Fades streamed text in as it arrives, the way agent apps reveal a reply,
/// instead of letting each token pop into place.
///
/// The text view's string is replaced on every token, so each update fades in
/// whatever lies past the end of the previous one. The fade is drawn with the
/// layout manager's temporary attributes: they change only how glyphs are coloured,
/// never the layout, so fading costs no relayout and cannot shift the text.
@MainActor
final class StreamingTextFade: NSObject {
    /// Seconds for new text to reach full strength.
    static let duration: CFTimeInterval = 0.35

    weak var textView: NSTextView?

    private var renderedLength = 0
    private var fades: [(range: NSRange, start: CFTimeInterval)] = []
    private var displayLink: CADisplayLink?

    /// Call straight after the text view's string has been replaced with `content`.
    func textDidChange(to content: NSAttributedString) {
        let previousLength = renderedLength
        renderedLength = content.length

        // Fades for characters that no longer exist are dropped; the rest are
        // drawn again below, onto the new string.
        fades = fades.filter { $0.range.upperBound <= content.length }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if content.length > previousLength, !reduceMotion {
            let added = NSRange(location: previousLength, length: content.length - previousLength)
            fades.append((added, CACurrentMediaTime()))
        }

        draw(at: CACurrentMediaTime())
        if !fades.isEmpty { startTicking() }
    }

    private func startTicking() {
        guard displayLink == nil, let textView else { return }
        let link = textView.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        draw(at: CACurrentMediaTime())
        if fades.isEmpty {
            // Invalidated rather than paused: the link holds this object, so it
            // must let go once there is nothing left to fade.
            link.invalidate()
            displayLink = nil
        }
    }

    /// Recolours every fading range for `now` and retires the finished ones.
    private func draw(at now: CFTimeInterval) {
        guard let textView, let layoutManager = textView.layoutManager,
            let storage = textView.textStorage
        else {
            fades = []
            return
        }

        // Cleared first, so nothing left over from the replaced string lingers.
        let whole = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)

        let baseColor = textView.textColor ?? .labelColor
        fades = fades.filter { fade in
            let progress = min(1, (now - fade.start) / Self.duration)
            guard progress < 1 else { return false }

            // Ease out: quick to appear, gentle to settle.
            let strength = 1 - pow(1 - progress, 3)
            storage.enumerateAttribute(.foregroundColor, in: fade.range) { value, run, _ in
                let color = (value as? NSColor) ?? baseColor
                layoutManager.addTemporaryAttribute(
                    .foregroundColor,
                    value: color.withAlphaComponent(color.alphaComponent * strength),
                    forCharacterRange: run
                )
            }
            return true
        }
    }
}
