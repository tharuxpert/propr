import AppKit
import Foundation
import Testing
import WebKit

@testable import Propr

struct SearchPanelTests {
    @Test("Only Google and AI appear in lookup")
    func availableProviders() {
        #expect(SearchProvider.allCases == [.google, .ai])
    }

    @Test("Google searches the complete edited phrase")
    func providerSearchURL() {
        let query = "rejection & Swift/Unicode 👋"
        let url = SearchProvider.google.searchURL(for: query)
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        #expect(url?.scheme == "https")
        #expect(url?.host == "www.google.com")
        #expect(components?.queryItems?.contains { $0.value == query } == true)
    }

    @Test("Empty queries do not navigate", arguments: SearchProvider.allCases)
    func emptyQuery(provider: SearchProvider) {
        #expect(provider.searchURL(for: "  \n") == nil)
    }

    @MainActor
    @Test("Web results use Scry's desktop Safari presentation without blanket styling")
    func scryWebPresentation() {
        let google = SearchWebPresentation.makeConfiguration(for: .google)
        #expect(google.websiteDataStore === WKWebsiteDataStore.default())
        #expect(google.applicationNameForUserAgent == "Safari/605.1.15")
        #expect(google.defaultWebpagePreferences.preferredContentMode == .recommended)
        #expect(google.userContentController.userScripts.count == 1)
        #expect(google.userContentController.userScripts[0].injectionTime == .atDocumentEnd)
        #expect(google.userContentController.userScripts[0].source.contains("dismissConsent"))

        #expect(SearchWebPresentation.makeConfiguration(for: .ai)
            .userContentController.userScripts.isEmpty)
    }

    @Test("AI lookup sends the latest query with Propr's endpoint and credentials")
    func aiLookupRequest() throws {
        let selection = ModelSelection(
            id: UUID(), displayName: "Test Model", endpointID: UUID(),
            modelName: "test-model", baseURL: "https://api.example.com/v1"
        )
        let request = try AILookupRequest(
            query: "the edited query", selection: selection,
            apiKey: "test-key", imageContext: nil
        ).makeURLRequest()
        let body = try #require(request.httpBody)
        let payload = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(payload["messages"] as? [[String: Any]])

        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(payload["model"] as? String == "test-model")
        #expect(payload["temperature"] as? Double == 0.4)
        #expect(messages[0]["content"] as? String == AILookupRequest.systemPrompt)
        #expect(messages[1]["content"] as? String == "What does the edited query mean?")
        #expect(payload["max_tokens"] as? Int == 160)
        #expect(AILookupRequest.systemPrompt.contains("Include slang only when"))
        #expect(AILookupRequest.systemPrompt.contains("definition on its own line"))
        #expect(AILookupRequest.systemPrompt.contains("example in quotation marks on the following line"))
        #expect(AILookupRequest.systemPrompt.contains("one common meaning"))
        #expect(AILookupRequest.systemPrompt.contains("**Noun**"))
        #expect(AILookupRequest.systemPrompt.contains("separate compact Markdown block"))
    }

    @Test("Direct questions stay direct while words become meaning questions")
    func aiLookupPrompt() {
        #expect(AILookupRequest.userPrompt(for: "integration") == "What does integration mean?")
        #expect(AILookupRequest.userPrompt(for: "What is integration?") == "What is integration?")
        #expect(AILookupRequest.userPrompt(for: "Explain integration") == "Explain integration")
    }

    @MainActor
    @Test("AI answer renders Markdown and reflows tables for the narrow panel")
    func aiAnswerFormatting() {
        let answer = """
            **Integration** connects separate parts.

            | Term | Meaning |
            | --- | --- |
            | *Slang* | Social inclusion |

            See [more](https://example.com).
            """
        let rendered = SearchAnswerFormatter.render(answer)
        #expect(rendered.string.contains("Integration connects separate parts."))
        #expect(rendered.string.contains("Slang\nMeaning: Social inclusion"))
        #expect(rendered.string.contains("See more."))
        #expect(!rendered.string.contains("**"))
        #expect(!rendered.string.contains("| --- |"))
        let boldRange = (rendered.string as NSString).range(of: "Integration")
        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let linkRange = (rendered.string as NSString).range(of: "more")
        #expect(rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
            == URL(string: "https://example.com"))
    }

    @MainActor
    @Test("Part-of-speech labels render bold above their meanings")
    func aiPartOfSpeechFormatting() {
        let answer = """
            **Adjective**
            Short in time.
            “A brief meeting.”

            **Noun**
            A short summary.
            “A project brief.”
            """
        let rendered = SearchAnswerFormatter.render(answer)
        #expect(rendered.string.contains("Adjective\nShort in time.\n“A brief meeting.”"))
        #expect(rendered.string.contains("Noun\nA short summary.\n“A project brief.”"))
        let nounRange = (rendered.string as NSString).range(of: "Noun")
        let nounFont = rendered.attribute(.font, at: nounRange.location, effectiveRange: nil) as? NSFont
        #expect(nounFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @MainActor
    @Test("Inline code renders monospace without backticks")
    func inlineCodeFormatting() {
        let rendered = SearchAnswerFormatter.render(
            "run it with `python hello.py` on your system")
        #expect(rendered.string.contains("run it with python hello.py on your system"))
        #expect(!rendered.string.contains("`"))
        let codeRange = (rendered.string as NSString).range(of: "python hello.py")
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        #expect(codeFont?.fontName.localizedCaseInsensitiveContains("mono") == true)
    }

    @MainActor
    @Test("Fenced code blocks drop fences without extra gaps")
    func fencedCodeBlockFormatting() {
        let rendered = SearchAnswerFormatter.render(
            "Two easy options:\n\n```python\nprint(\"Hello\")\n```\n\nor two calls:")
        #expect(!rendered.string.contains("```"))
        #expect(!rendered.string.contains("\n\n\n"))
        #expect(rendered.string == "Two easy options:\n\nprint(\"Hello\")\n\nor two calls:")
        let codeRange = (rendered.string as NSString).range(of: "print(\"Hello\")")
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        #expect(codeFont?.fontName.localizedCaseInsensitiveContains("mono") == true)
        #expect(rendered.attribute(.proprCode, at: codeRange.location, effectiveRange: nil) as? Bool == true)
    }

    @MainActor
    @Test("Blank lines inside a code block are kept")
    func codeBlockKeepsInnerBlanks() {
        let rendered = SearchAnswerFormatter.render("```\nline one\n\nline two\n```")
        #expect(rendered.string == "line one\n\nline two")
        let range = (rendered.string as NSString).range(of: "line two")
        #expect(rendered.attribute(.proprCode, at: range.location, effectiveRange: nil) as? Bool == true)
    }

    @MainActor
    @Test("Inline code is marked for pill drawing")
    func inlineCodePillMark() {
        let rendered = SearchAnswerFormatter.render(
            "run it with `python hello.py` on your system")
        let codeRange = (rendered.string as NSString).range(of: "python hello.py")
        #expect(rendered.attribute(.proprCode, at: codeRange.location, effectiveRange: nil) as? Bool == false)
        let plainRange = (rendered.string as NSString).range(of: "run it")
        #expect(rendered.attribute(.proprCode, at: plainRange.location, effectiveRange: nil) == nil)
    }

    @MainActor
    @Test("Pill layout manager paints behind marked code")
    func pillLayoutPaints() {
        let content = SearchAnswerFormatter.render(
            "Two options:\n\n```\nline one\nline two\n```\n\npick one")
        func paintedPixels(withPills pills: Bool) -> Int {
            guard let rep = paintedAnswer(content: content, pills: pills) else { return 0 }
            var count = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                        count += 1
                    }
                }
            }
            return count
        }
        #expect(paintedPixels(withPills: true) > paintedPixels(withPills: false))
    }

    @MainActor
    @Test("Code block pills hug the code instead of spanning the panel")
    func codeBlockPillHugsCode() {
        let content = SearchAnswerFormatter.render("```\nline one\nline two\n```")
        guard let pills = paintedAnswer(content: content, pills: true),
              let plain = paintedAnswer(content: content, pills: false)
        else {
            Issue.record("could not paint answer offscreen")
            return
        }
        // Pill-only pixels (painted with pills, absent without) must stay near
        // the short code lines — "line two" ends around x=70 in a 400pt view.
        // The newline-stretch bug painted them all the way to x=400.
        var rightmostPillOnly = 0
        for x in 0..<pills.pixelsWide {
            for y in 0..<pills.pixelsHigh {
                let pillAlpha = pills.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let plainAlpha = plain.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if pillAlpha > 0.01, plainAlpha <= 0.01 {
                    rightmostPillOnly = x
                }
            }
        }
        #expect(rightmostPillOnly > 0)
        #expect(rightmostPillOnly < 200)
    }

    @MainActor
    @Test("First-line code is not clipped from the top")
    func firstLineCodeNotClipped() {
        let content = SearchAnswerFormatter.render("`print()` writes text to the console")
        let height = AnswerTextSizing.height(for: content, width: 400, maxHeight: 2000)
        #expect(height > 0)
        guard let pills = paintedAnswer(content: content, pills: true, height: height),
              let plain = paintedAnswer(content: content, pills: false, height: height)
        else {
            Issue.record("could not paint answer offscreen")
            return
        }
        // Pill-only pixels must exist but touch neither horizontal edge: a
        // short frame shaves the top, right where a first-line pill sits.
        var anyPillOnly = false
        var edgePillOnly = 0
        for x in 0..<pills.pixelsWide {
            for y in 0..<pills.pixelsHigh {
                let pillAlpha = pills.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let plainAlpha = plain.colorAt(x: x, y: y)?.alphaComponent ?? 0
                guard pillAlpha > 0.01, plainAlpha <= 0.01 else { continue }
                anyPillOnly = true
                if y == 0 || y == pills.pixelsHigh - 1 {
                    edgePillOnly += 1
                }
            }
        }
        #expect(anyPillOnly)
        #expect(edgePillOnly == 0)
    }

    @MainActor
    @Test("Redrawing part of a code block paints the same pill as a full draw")
    func partialRedrawKeepsBlockWhole() {
        let content = SearchAnswerFormatter.render(
            "```\nline one\nline two\n\nline four\nline five\n```")
        let storage = NSTextStorage(attributedString: content)
        let layout = PillBackgroundLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        // Scrolling or selecting redraws only some lines: here, from "line four".
        let start = (storage.string as NSString).range(of: "line four").location
        let partial = layout.glyphRange(
            forCharacterRange: NSRange(location: start, length: storage.length - start),
            actualCharacterRange: nil)
        let redrawTop = Int(layout.lineFragmentRect(forGlyphAt: partial.location, effectiveRange: nil).minY)

        func paint(_ glyphs: NSRange) -> NSBitmapImageRep? {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 420, pixelsHigh: 200,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep)
            else { return nil }
            NSGraphicsContext.saveGraphicsState()
            context.cgContext.translateBy(x: 0, y: 200)
            context.cgContext.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            layout.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 10, y: 0))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        guard let full = paint(layout.glyphRange(for: container)), let part = paint(partial) else {
            Issue.record("could not paint pills offscreen")
            return
        }
        // Within the redrawn rows the pill must match the full draw exactly;
        // the old code rounded fresh corners at the top of the redraw.
        var mismatches = 0
        for y in redrawTop..<200 {
            for x in 0..<420 {
                let a = full.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let b = part.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if abs(a - b) > 0.01 { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
    }

    /// Paints answer content offscreen at 400pt wide, with or without pills.
    @MainActor
    private func paintedAnswer(
        content: NSAttributedString, pills: Bool, height: CGFloat = 400
    ) -> NSBitmapImageRep? {
        let size = NSSize(width: 400, height: max(height, 1))
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        // Same geometry as the live answer view: the insets are what keep a
        // first-line pill clear of the edges.
        textView.textContainerInset = NSSize(
            width: AnswerTextSizing.horizontalInset,
            height: AnswerTextSizing.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        if pills {
            textView.textContainer?.replaceLayoutManager(PillBackgroundLayoutManager())
        }
        textView.drawsBackground = false
        textView.textStorage?.setAttributedString(content)
        guard let container = textView.textContainer else { return nil }
        textView.layoutManager?.ensureLayout(for: container)
        let image = NSImage(size: size)
        image.lockFocus()
        textView.draw(textView.bounds)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    @MainActor
    @Test("Answer height hugs short text and caps long text")
    func answerTextSizing() {
        let short = SearchAnswerFormatter.render("Hello.")
        let shortHeight = AnswerTextSizing.height(for: short, width: 446, maxHeight: 260)
        #expect(shortHeight > 0 && shortHeight < 260)
        #expect(AnswerTextSizing.height(
            for: NSAttributedString(string: ""), width: 446, maxHeight: 260) == 0)
        let long = SearchAnswerFormatter.render(
            (0..<200).map { "line \($0)" }.joined(separator: "\n"))
        #expect(AnswerTextSizing.height(for: long, width: 446, maxHeight: 260) == 260)
    }

    @MainActor
    @Test("Italic renders slanted without asterisks")
    func italicFormatting() {
        let rendered = SearchAnswerFormatter.render("This is *important* news.")
        #expect(rendered.string.contains("This is important news."))
        #expect(!rendered.string.contains("*"))
        let range = (rendered.string as NSString).range(of: "important")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontName.localizedCaseInsensitiveContains("italic") == true)
    }

    @MainActor
    @Test("Strikethrough renders struck without tildes")
    func strikethroughFormatting() {
        let rendered = SearchAnswerFormatter.render("That price is ~~gone~~ now.")
        #expect(rendered.string.contains("That price is gone now."))
        #expect(!rendered.string.contains("~~"))
        let range = (rendered.string as NSString).range(of: "gone")
        let style = rendered.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
        #expect(style == NSUnderlineStyle.single.rawValue)
    }

    @MainActor
    @Test("Blockquotes lose the marker but keep the content")
    func blockquoteFormatting() {
        let rendered = SearchAnswerFormatter.render("> **Hello**, World!")
        #expect(!rendered.string.contains(">"))
        #expect(rendered.string.contains("Hello, World!"))
        let range = (rendered.string as NSString).range(of: "Hello")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @MainActor
    @Test("Nested bullets keep their indent instead of flattening")
    func nestedBulletsKeepIndent() {
        let rendered = SearchAnswerFormatter.render("- top\n  - nested\n    - deep")
        #expect(rendered.string == "• top\n  • nested\n    • deep")
    }

    @MainActor
    @Test("Task lists render checkboxes without brackets")
    func taskListFormatting() {
        let rendered = SearchAnswerFormatter.render("- [ ] todo\n- [x] done")
        #expect(rendered.string == "☐ todo\n☑ done")
    }

    @MainActor
    @Test("A horizontal rule renders as a divider line")
    func horizontalRuleFormatting() {
        for marker in ["---", "***", "___"] {
            let rendered = SearchAnswerFormatter.render("above\n\(marker)\nbelow")
            #expect(!rendered.string.contains(marker))
            #expect(rendered.string.contains("above\n"))
            #expect(rendered.string.contains("\nbelow"))
        }
    }

    @MainActor
    @Test("Numbered lists read as-is with inner formatting kept")
    func numberedListPassthrough() {
        let rendered = SearchAnswerFormatter.render("1. first\n2. **second**")
        #expect(rendered.string == "1. first\n2. second")
        let range = (rendered.string as NSString).range(of: "second")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @MainActor
    @Test("Emphasis survives the SwiftUI AttributedString conversion")
    func emphasisSurvivesConversion() {
        let converted = AttributedString(SearchAnswerFormatter.render(
            "This is **bold** and *italic* with `code`."))
        let back = NSAttributedString(converted)
        func fontName(of text: String) -> String {
            let range = (back.string as NSString).range(of: text)
            return (back.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.fontName ?? ""
        }
        #expect(fontName(of: "bold").localizedCaseInsensitiveContains("bold"))
        #expect(fontName(of: "italic").localizedCaseInsensitiveContains("italic"))
        #expect(fontName(of: "code").localizedCaseInsensitiveContains("mono"))
    }

    @Test("Optional image context is included only when supplied")
    func aiLookupImageContext() throws {
        let selection = ModelSelection(
            id: UUID(), displayName: "Test Model", endpointID: UUID(),
            modelName: "test-model", baseURL: "https://api.example.com/v1"
        )
        let image = SearchImageContext(data: Data([1, 2, 3]), mimeType: "image/png")
        let payload = AILookupRequest(
            query: "What is this?", selection: selection,
            apiKey: "", imageContext: image
        ).payload
        let messages = try #require(payload["messages"] as? [[String: Any]])
        let segments = try #require(messages[1]["content"] as? [[String: Any]])

        #expect(segments[0]["text"] as? String == "What is this?")
        let imageURL = try #require(segments[1]["image_url"] as? [String: String])
        #expect(imageURL["url"] == "data:image/png;base64,AQID")
    }
}
