import AppKit
import SwiftUI

/// An answer to a question about the text, shown in the bar instead of the document.
///
/// Streams in as it arrives. Once complete it can be copied, or — if an edit was
/// what the user actually wanted — the same instruction can be run again as one.
struct AnswerSection: View {
    let answer: FloatingBarSessionState.Answer
    let onEditInstead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The prompt clears once the answer is in, so keep what was asked in view.
            Text(answer.question)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, -4)

            Text(answer.text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(14)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if answer.isComplete {
                HStack(spacing: 8) {
                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer.text, forType: .string)
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
