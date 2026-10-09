import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Marks a run as code for pill drawing. The value is a Bool: true for a
    /// fenced-block line, false for inline code. Carries no color itself; the
    /// pill color lives in `PillStyle` so light and dark mode stay in one place.
    static let proprCode = NSAttributedString.Key("ProprCodePill")
}

/// Look of the code pills drawn behind code runs.
enum PillStyle {
    static let background = NSColor.labelColor.withAlphaComponent(0.12)
    /// Breathing room on the two sides of a pill.
    static let sidePadding: CGFloat = 4
    static let verticalPadding: CGFloat = 2
    static let cornerRadius: CGFloat = 5
}

/// Draws rounded pills behind the ranges `SearchAnswerFormatter` marks with
/// `.proprCode`. A plain `backgroundColor` fill is always a sharp rectangle
/// with no padding, which is what made code look pasted-on.
///
/// Inline code gets one pill per line fragment, so a wrapped span never paints
/// over the prose between its lines. Consecutive fenced-block lines merge into
/// a single continuous block; the bounding box only ever covers trailing
/// whitespace, which is invisible.
final class PillBackgroundLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodePills(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawCodePills(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let fullText = storage.string as NSString
        for container in textContainers {
            let containerGlyphs = NSIntersectionRange(glyphRange(for: container), glyphsToShow)
            guard containerGlyphs.length > 0 else { continue }
            let chars = characterRange(forGlyphRange: containerGlyphs, actualGlyphRange: nil)

            var spans: [(range: NSRange, isBlock: Bool)] = []
            storage.enumerateAttribute(.proprCode, in: chars, options: []) { value, range, _ in
                guard let isBlock = value as? Bool else { return }
                if isBlock, let last = spans.last, last.isBlock,
                   gapIsOnlyNewlines(fullText, from: last.range.upperBound, to: range.location) {
                    spans[spans.count - 1].range = NSRange(
                        location: last.range.location,
                        length: range.upperBound - last.range.location)
                } else {
                    spans.append((range, isBlock))
                }
            }

            for span in spans {
                let glyphs = glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
                var rects: [NSRect] = []
                enumerateEnclosingRects(
                    forGlyphRange: glyphs,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: container
                ) { rect, _ in
                    rects.append(rect)
                }
                guard !rects.isEmpty else { continue }
                if span.isBlock {
                    var union = rects[0]
                    for rect in rects.dropFirst() { union = union.union(rect) }
                    fillPill(union, at: origin)
                } else {
                    for rect in rects { fillPill(rect, at: origin) }
                }
            }
        }
    }

    private func gapIsOnlyNewlines(_ text: NSString, from start: Int, to end: Int) -> Bool {
        guard start <= end, end <= text.length else { return false }
        let gap = text.substring(with: NSRange(location: start, length: end - start))
        return gap.allSatisfy { $0 == "\n" }
    }

    private func fillPill(_ rect: NSRect, at origin: NSPoint) {
        var padded = rect.insetBy(dx: -PillStyle.sidePadding, dy: -PillStyle.verticalPadding)
        padded.origin.x += origin.x
        padded.origin.y += origin.y
        PillStyle.background.setFill()
        NSBezierPath(
            roundedRect: padded,
            xRadius: PillStyle.cornerRadius, yRadius: PillStyle.cornerRadius
        ).fill()
    }
}

/// Measures answer text with the same insets the live view uses, so the panel
/// can size to fit without a layout feedback loop.
enum AnswerTextSizing {
    static let horizontalInset: CGFloat = 4
    static let verticalInset: CGFloat = 5

    static func height(for content: NSAttributedString, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        guard content.length > 0, width > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: content)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(
            width: width - horizontalInset * 2, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return min(max(0, used.height + verticalInset * 2), maxHeight)
    }
}

/// The answer body as a real text view, so code pills draw rounded and text
/// stays selectable. Mirrors the insets `AnswerTextSizing` measures with.
struct AnswerTextView: NSViewRepresentable {
    var content: NSAttributedString
    var width: CGFloat
    var maxHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.textContainer?.replaceLayoutManager(PillBackgroundLayoutManager())
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = false
        // Code must never come back smart-quoted.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(
            width: AnswerTextSizing.horizontalInset,
            height: AnswerTextSizing.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Streaming replaces the string on every token; keep the user's
        // selection and scroll position instead of resetting them.
        let selection = textView.selectedRanges
        let visible = textView.visibleRect
        textView.textStorage?.setAttributedString(content)
        textView.selectedRanges = selection.filter {
            $0.rangeValue.upperBound <= content.length
        }
        textView.scrollToVisible(visible)
        let fitted = AnswerTextSizing.height(for: content, width: width, maxHeight: maxHeight)
        textView.frame = NSRect(x: 0, y: 0, width: max(width, 1), height: max(fitted, 1))
        scrollView.hasVerticalScroller = fitted >= maxHeight && content.length > 0
    }
}
