import AppKit
import SwiftUI

/// An answer to a question about the text, shown in the bar instead of the document.
///
/// Streams in as it arrives and can be copied once complete. If an edit was what
/// the user wanted, a follow-up such as "do it" makes one: the answer is in the
/// session history, so the model knows what "it" is.
struct AnswerSection: View {
    let answer: FloatingBarSessionState.Answer

    /// About fourteen lines of body text before the answer scrolls.
    private static let maxAnswerHeight: CGFloat = 260

    /// Fallback text width until layout reports the real one: the 500pt panel
    /// minus this section's leading and trailing insets.
    @State private var textWidth: CGFloat = 500 - 42 - 12

    /// The model's lightweight Markdown, rendered the same way as lookup answers.
    /// Unfinished markup mid-stream falls back to plain text per line inside the
    /// formatter, so this is safe to call on every streamed token.
    private var content: NSAttributedString {
        SearchAnswerFormatter.render(answer.text)
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

            // A real text view so code pills draw rounded with side padding —
            // SwiftUI Text can only paint sharp, padding-less fills. Hugs a short
            // answer; a long one (lists, reflowed tables) scrolls once it reaches
            // the cap instead of being cut off. The height is measured with the
            // same insets the view uses, so the panel grows to fit it.
            AnswerTextView(content: content, width: textWidth, maxHeight: Self.maxAnswerHeight)
                .frame(height: AnswerTextSizing.height(
                    for: content, width: textWidth, maxHeight: Self.maxAnswerHeight))
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { textWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in textWidth = width }
                    }
                )

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
