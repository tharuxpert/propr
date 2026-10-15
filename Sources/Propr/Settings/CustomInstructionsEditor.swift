import SwiftUI

/// The text box for a section's standing custom instructions: placeholder,
/// character cap, counter and an explanatory note.
///
/// The Refine and Lookup panes each own one, so the two boxes cannot drift apart
/// in look or in the limit they enforce.
struct CustomInstructionsEditor: View {
    let placeholder: String
    let note: String
    let limit: Int
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 96, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(verbatim: placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { _, newValue in
                    if newValue.count > limit {
                        text = String(newValue.prefix(limit))
                    }
                }
                .accessibilityLabel("Custom Instructions")

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SettingsNote(note)
                Spacer(minLength: 0)
                Text("\(text.count) / \(limit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        // A text editor reports no baseline, so the columns form would hang its label
        // above the box. Report the first line's baseline (box inset plus one line)
        // so the label reads level with the text inside.
        .alignmentGuide(.firstTextBaseline) { d in d[.top] + 19 }
    }
}
