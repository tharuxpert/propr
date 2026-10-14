import SwiftUI

/// The text box for a section's standing custom instructions: badged label,
/// placeholder, character cap and counter.
///
/// The Refine and Lookup sections each own one, so the two boxes cannot drift apart
/// in look or in the limit they enforce.
struct CustomInstructionsEditor: View {
    let title: String
    let systemImage: String
    let color: Color
    let subtitle: String
    let placeholder: String
    let limit: Int
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRowLabel(
                title: title,
                systemImage: systemImage,
                color: color,
                subtitle: subtitle
            )

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 64, maxHeight: 120)
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

            Text("\(text.count) / \(limit)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
