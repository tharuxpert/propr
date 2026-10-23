import SwiftUI

/// The quick prompt pills under the bar. A click, or ⌘1 to ⌘6, sends one.
///
/// On macOS 26 each pill is its own glass shape in the bar's glass group, so the
/// pills flow out of the bar when they appear and back into it when they go.
struct QuickPromptRow: View {
    let prompts: [QuickPrompt]
    let isEnabled: Bool
    let glassNamespace: Namespace.ID
    /// A stand-in that only reserves the row's space while the real pills animate
    /// away, so it draws nothing and takes no glass IDs or shortcuts.
    var isPlaceholder = false
    let onSend: (QuickPrompt) -> Void

    static let spacing: CGFloat = 8

    var body: some View {
        PillFlowLayout(spacing: Self.spacing) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                pill(prompt, number: index + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pill(_ prompt: QuickPrompt, number: Int) -> some View {
        let button = Button {
            onSend(prompt)
        } label: {
            QuickPromptPillLabel(prompt: prompt)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help("\(prompt.mode.title): \(prompt.text) (⌘\(number))")

        if isPlaceholder {
            button.hidden()
        } else {
            button
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                .modifier(QuickPromptPillSurface(id: prompt.id, glassNamespace: glassNamespace))
        }
    }
}

/// A pill's text, with a small mark for whether it answers or edits.
private struct QuickPromptPillLabel: View {
    let prompt: QuickPrompt

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: prompt.mode == .ask ? "questionmark.bubble" : "pencil.line")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(prompt.instruction ?? prompt.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Capsule())
    }
}

/// Glass for each pill on macOS 26; the bar's own vibrancy, as a capsule, before it.
private struct QuickPromptPillSurface: ViewModifier {
    let id: UUID
    let glassNamespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID(id, in: glassNamespace)
        } else {
            content
                .background(Color.black.opacity(0.3))
                .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 13))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

/// Lays pills out left to right, wrapping onto a new line when the next one would
/// not fit.
private struct PillFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            // A single pill wider than the row is squeezed to fit rather than overflowing.
            let ideal = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(ideal.width, width), height: ideal.height)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
