import AppKit

/// Renders the small amount of Markdown a lookup model may return without
/// flattening paragraphs or showing markup characters in the answer panel.
@MainActor
enum SearchAnswerFormatter {
    private static let bodyFont = NSFont.systemFont(ofSize: 14)

    /// Backdrop for code, subtle in both light and dark mode.
    private static let codeBackground = NSColor.labelColor.withAlphaComponent(0.12)

    static func render(_ answer: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        let lines = normalizeBreaks(reflowTables(answer)).components(separatedBy: "\n")
        var inCodeBlock = false
        var needsNewline = false
        var lastWasBlank = true

        /// Fence markers emit nothing at all (not even a separator), and runs of
        /// blank lines collapse to one — otherwise a fenced block surrounded by
        /// blank lines renders with double gaps above and below the code.
        func append(_ part: NSAttributedString) {
            let isBlank = part.length == 0
            if isBlank, lastWasBlank { return }
            if needsNewline {
                output.append(NSAttributedString(string: "\n"))
            }
            output.append(part)
            needsNewline = true
            lastWasBlank = isBlank
        }

        for originalLine in lines {
            let trimmed = originalLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
            } else if inCodeBlock {
                append(NSAttributedString(
                    string: originalLine,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                                 .foregroundColor: NSColor.labelColor,
                                 .backgroundColor: codeBackground]))
            } else {
                var line = originalLine
                let font = bodyFont
                if line.range(
                    of: #"^\s{0,3}(-{3,}|_{3,}|\*{3,})\s*$"#,
                    options: .regularExpression
                ) != nil {
                    append(NSAttributedString(
                        string: String(repeating: "─", count: 16),
                        attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
                } else if let heading = line.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
                    line.removeSubrange(heading)
                    append(inline(line, baseFont: .systemFont(ofSize: 15, weight: .semibold)))
                } else if let task = line.range(
                    of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression
                ) {
                    let box = line[task].contains("x") || line[task].contains("X") ? "☑ " : "☐ "
                    line.replaceSubrange(task, with: indent(of: line, in: task) + box)
                    append(inline(line, baseFont: font))
                } else if let bullet = line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) {
                    line.replaceSubrange(bullet, with: indent(of: line, in: bullet) + "• ")
                    append(inline(line, baseFont: font))
                } else if let quote = line.range(of: #"^\s{0,3}>\s?"#, options: .regularExpression) {
                    line.removeSubrange(quote)
                    let quoted = NSMutableAttributedString(string: "│ ", attributes: [
                        .font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    quoted.append(inline(line, baseFont: font))
                    append(quoted)
                } else {
                    // Numbered lists need no rewriting: "1. ..." reads as-is and the
                    // inline pass below still styles any emphasis or code inside.
                    append(inline(line, baseFont: font))
                }
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        output.addAttribute(.paragraphStyle, value: paragraph,
                            range: NSRange(location: 0, length: output.length))
        return output
    }

    private static func inline(_ line: String, baseFont: NSFont) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else {
            return NSAttributedString(
                string: line,
                attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor])
        }

        let output = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                if intent.contains(.code) {
                    font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                }
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor
            ]
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attributes[.backgroundColor] = codeBackground
            }
            if let intent = run.inlinePresentationIntent, intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let url = run.link, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                attributes[.link] = url
                attributes[.foregroundColor] = NSColor.linkColor
            }
            output.append(NSAttributedString(
                string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }

    private static func normalizeBreaks(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    }

    /// Leading whitespace of a matched list marker, so nested items keep their
    /// depth instead of flattening to the left edge.
    private static func indent(of line: String, in match: Range<String.Index>) -> String {
        String(line[match].prefix(while: { $0 == " " || $0 == "\t" }))
    }

    /// Tables are reformatted into stacked label/value lines so they remain
    /// readable in the narrow floating panel without horizontal scrolling.
    private static func reflowTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        while index < lines.count {
            guard index + 1 < lines.count,
                let headers = tableCells(lines[index]), headers.count > 1,
                let divider = tableCells(lines[index + 1]),
                divider.count == headers.count, divider.allSatisfy(isDivider)
            else {
                output.append(lines[index])
                index += 1
                continue
            }

            index += 2
            while index < lines.count, let cells = tableCells(lines[index]),
                  cells.count == headers.count {
                output.append("### \(cells[0])")
                for column in 1..<cells.count where !cells[column].isEmpty {
                    output.append("**\(headers[column]):** \(cells[column])")
                }
                output.append("")
                index += 1
            }
        }
        return output.joined(separator: "\n")
    }

    private static func tableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells.count > 1 ? cells : nil
    }

    private static func isDivider(_ cell: String) -> Bool {
        cell.filter { $0 == "-" }.count >= 3
            && cell.allSatisfy { $0 == "-" || $0 == ":" }
    }
}
