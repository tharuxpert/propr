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
///
/// Rects are measured per line with newlines excluded and clamped to the
/// glyphs' tight bounding box: a newline glyph's rect can stretch to the
/// container edge, which once blew every block out to full panel width.
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

            // A block is a group of line ranges; inline code stands on its own.
            // Line ranges never include their newlines (see the class docs).
            //
            // Blocks are widened to their full extent, not just the redrawn
            // lines: a partial redraw (scrolling, selecting) otherwise rounds
            // the pill's corners mid-block and leaves a notch.
            var groups: [(lines: [NSRange], isBlock: Bool)] = []
            var coveredBlockEnd = 0
            storage.enumerateAttribute(.proprCode, in: chars, options: []) { value, range, _ in
                guard let isBlock = value as? Bool else { return }
                if isBlock {
                    guard range.location >= coveredBlockEnd else { return }
                    let extent = blockExtent(around: range, in: storage)
                    coveredBlockEnd = extent.upperBound
                    let lines = lineRanges(in: extent, text: fullText)
                    if !lines.isEmpty { groups.append((lines, true)) }
                } else {
                    groups.append(([range], false))
                }
            }

            for group in groups {
                var rects: [NSRect] = []
                for line in group.lines {
                    rects.append(contentsOf: pills(
                        forLineCharacters: line, in: container))
                }
                guard !rects.isEmpty else { continue }
                if group.isBlock {
                    var union = rects[0]
                    for rect in rects.dropFirst() { union = union.union(rect) }
                    fillPill(union, at: origin)
                } else {
                    for rect in rects { fillPill(rect, at: origin) }
                }
            }
        }
    }

    /// Splits a marked range into its line ranges, dropping the newlines.
    private func lineRanges(in range: NSRange, text: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var loc = range.location
        while loc < range.upperBound {
            var lineEnd = loc
            while lineEnd < range.upperBound, text.character(at: lineEnd) != 10 {
                lineEnd += 1
            }
            if lineEnd > loc {
                lines.append(NSRange(location: loc, length: lineEnd - loc))
            }
            loc = lineEnd + 1
        }
        return lines
    }

    /// One pill per line fragment in a marked line range. Each pill hugs its
    /// own glyphs — full line boxes made the pills tall and heavy — and stays
    /// centered on its line, so the gaps between lines and the words beside
    /// the code are untouched. Walking fragments explicitly (instead of
    /// `enumerateEnclosingRects`) keeps a wrapped run's pills tight to each
    /// fragment rather than smearing across the whole line width.
    private func pills(
        forLineCharacters line: NSRange, in container: NSTextContainer
    ) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: line, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return [] }
        var pills: [NSRect] = []
        var loc = glyphs.location
        while loc < glyphs.upperBound {
            var fragmentGlyphs = NSRange(location: 0, length: 0)
            let fragment = lineFragmentRect(forGlyphAt: loc, effectiveRange: &fragmentGlyphs)
            guard fragmentGlyphs.length > 0 else { break }
            let part = NSIntersectionRange(fragmentGlyphs, glyphs)
            guard part.length > 0 else { break }
            let tight = boundingRect(forGlyphRange: part, in: container)
            if tight.width > 0, tight.height > 0 {
                // Hug the glyphs but never leave the line box: an overhang
                // past the first fragment's top is exactly what reads as a
                // pill clipped from above.
                let height = min(
                    tight.height + PillStyle.verticalPadding * 2, fragment.height)
                pills.append(NSRect(
                    x: tight.minX, y: fragment.midY - height / 2,
                    width: tight.width, height: height))
            }
            loc = part.upperBound
        }
        return pills
    }

    /// Grows a block-line run to the whole block: neighbouring block lines
    /// separated only by newlines (blank lines inside a block included).
    private func blockExtent(around range: NSRange, in storage: NSTextStorage) -> NSRange {
        let text = storage.string as NSString
        func isBlock(at index: Int) -> Bool {
            storage.attribute(.proprCode, at: index, effectiveRange: nil) as? Bool == true
        }
        var lower = range.location
        var upper = range.upperBound
        while true {
            var gapStart = lower
            while gapStart > 0, text.character(at: gapStart - 1) == 10 { gapStart -= 1 }
            guard gapStart < lower, gapStart > 0, isBlock(at: gapStart - 1) else { break }
            var run = NSRange(location: 0, length: 0)
            storage.attribute(.proprCode, at: gapStart - 1, longestEffectiveRange: &run,
                              in: NSRange(location: 0, length: gapStart))
            lower = run.location
        }
        while true {
            var gapEnd = upper
            while gapEnd < text.length, text.character(at: gapEnd) == 10 { gapEnd += 1 }
            guard gapEnd > upper, gapEnd < text.length, isBlock(at: gapEnd) else { break }
            var run = NSRange(location: 0, length: 0)
            storage.attribute(.proprCode, at: gapEnd, longestEffectiveRange: &run,
                              in: NSRange(location: gapEnd, length: text.length - gapEnd))
            upper = run.upperBound
        }
        return NSRange(location: lower, length: upper - lower)
    }

    private func fillPill(_ rect: NSRect, at origin: NSPoint) {
        // Pills arrive with their vertical extent final; only the side
        // breathing room is added here.
        var padded = rect.insetBy(dx: -PillStyle.sidePadding, dy: 0)
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
///
/// Measured to the last line fragment's edge, not the glyph bounding box:
/// the glyph box skips line leading and comes up a few points short, and a
/// short frame shaves the top — which is exactly where a first-line code
/// pill sits.
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
///
/// The caller measures once and passes `fittedHeight` in; the text view sizes
/// its own document height from layout, so long answers stay scrollable.
struct AnswerTextView: NSViewRepresentable {
    var content: NSAttributedString
    var fittedHeight: CGFloat
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
        scrollView.hasVerticalScroller = fittedHeight >= maxHeight && content.length > 0
    }
}
