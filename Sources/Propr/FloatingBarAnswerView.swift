import AppKit
import SwiftUI

/// An answer to a question about the text, shown in the bar instead of the document.
///
/// Streams in as it arrives. Once complete it can be copied, or — if an edit was
/// what the user actually wanted — the same instruction can be run again as one.
struct AnswerSection: View {
    let answer: FloatingBarSessionState.Answer
    let onEditInstead: () -> Void

    /// About fourteen lines of body text before the answer scrolls.
    private static let maxAnswerHeight: CGFloat = 260

    /// The model's lightweight Markdown, rendered the same way as lookup answers.
    /// Unfinished markup mid-stream falls back to plain text per line inside the
    /// formatter, so this is safe to call on every streamed token.
    private var renderedAnswer: AttributedString {
        AttributedString(SearchAnswerFormatter.render(answer.text))
    }

    /// What lands on the clipboard: the answer without markup characters, so
    /// `python hello.py` copies without its backticks.
    private var plainAnswer: String {
        SearchAnswerFormatter.render(answer.text).string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The prompt clears once the answer is in, so keep what was asked in view.
            Text(answer.question)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, -4)

            // Styled by SearchAnswerFormatter (body 14, bold/code/links); no .font /
            // .foregroundStyle here, since those modifiers would override the runs.
            //
            // Hugs a short answer; a long one (lists, reflowed tables) scrolls once it
            // reaches the cap instead of being cut off. The trailing fixedSize makes
            // the scroll view report its content height, capped, so the panel grows
            // to fit it.
            ScrollView {
                Text(renderedAnswer)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.maxAnswerHeight)
            .fixedSize(horizontal: false, vertical: true)

            if answer.isComplete {
                HStack(spacing: 8) {
                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(plainAnswer, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy the answer")

                    Button(action: onEditInstead) {
                        Label("Edit instead", systemImage: "pencil.line")
                    }
                    .help("Run “\(answer.question)” as a change to your text")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(KeycapButtonStyle())
            }
        }
        .padding(.leading, 42)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .transition(.opacity)
    }
}
