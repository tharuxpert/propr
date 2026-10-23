import SwiftUI

/// The quick prompt pills under the bar. A click, or ⌘1 to ⌘6, sends one.
///
/// The pills stay in the view while hidden, shrunk against the bar's bottom edge.
/// Showing and hiding moves them out and back in, so both directions animate the
/// same way, and on macOS 26 their glass flows into the bar's as they pass it.
struct QuickPromptRow: View {
    let prompts: [QuickPrompt]
    let isShown: Bool
    /// Whether the row keeps its height. Released a moment after the pills hide,
    /// once they are back under the bar, so the panel does not cut them off.
    let holdsSpace: Bool
    let isEnabled: Bool
    let glassNamespace: Namespace.ID
    let onSend: (QuickPrompt) -> Void

    /// Between the pills, and between the bar and the first line of them.
    static let spacing: CGFloat = 8

    /// The pills' own height, measured, so the row can reserve it while they
    /// are hidden.
    @State private var pillsHeight: CGFloat = 0

    var body: some View {
        PillFlowLayout(spacing: Self.spacing) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                pill(prompt, number: index + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillsHeight = $0 }
        // Hidden, the pills shrink against the bar's bottom edge; shown, they sit
        // one gap below it. They never pass under the bar, whose glass would show
        // them through it. Real layout rather than an offset, so the glass group
        // sees the pills move and blends them with the bar's edge on the way.
        .padding(.top, isShown ? Self.spacing : 0)
        .frame(height: holdsSpace ? Self.spacing + pillsHeight : 0, alignment: .top)
        .allowsHitTesting(isShown)
    }

    private func pill(_ prompt: QuickPrompt, number: Int) -> some View {
        Button {
            onSend(prompt)
        } label: {
            QuickPromptPillLabel(prompt: prompt)
        }
        .buttonStyle(.plain)
        // Disabled while hidden too, which also turns its shortcut off.
        .disabled(!isEnabled || !isShown)
        .help("\(prompt.mode.title): \(prompt.text) (⌘\(number))")
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .modifier(
            QuickPromptPillSurface(
                id: prompt.id,
                isShown: isShown,
                hasGlass: isShown || holdsSpace,
                glassNamespace: glassNamespace
            ))
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
    let isShown: Bool
    /// Off once a hidden pill has finished shrinking away: a zero-size glass
    /// shape still leaves a speck on the bar's edge.
    let hasGlass: Bool
    let glassNamespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // The glass group draws each glass shape and its content itself, so an
            // opacity or scale outside the glass is ignored. The label fades inside
            // it, and the glass shape itself shrinks to nothing against the bar's
            // edge, rim included. Switching the glass off instead let the rim
            // linger after the label had gone.
            hiding(content)
                .glassEffect(
                    hasGlass ? .regular.interactive() : .identity,
                    in: Capsule().scale(isShown ? 1 : 0, anchor: .top)
                )
                .glassEffectID(id, in: glassNamespace)
        } else {
            hiding(
                content
                    .background(Color.black.opacity(0.3))
                    .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 13))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            )
        }
    }

    private func hiding(_ view: some View) -> some View {
        view
            .scaleEffect(isShown ? 1 : 0.6, anchor: .top)
            .opacity(isShown ? 1 : 0)
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
