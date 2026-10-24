import SwiftUI

/// The bar's backdrop, rounding and edge.
///
/// From macOS 26 the bar is Liquid Glass, so it can share a `GlassEffectContainer`
/// with the quick prompt pills and they can flow out of it. Earlier systems keep the
/// behind-window vibrancy the bar has always had.
///
/// The working streak is not drawn here: anything inside the glass group is
/// rendered as part of the glass, which washed it out. The bar draws it on top.
struct FloatingBarSurface: ViewModifier {
    let cornerRadius: CGFloat
    let glassNamespace: Namespace.ID

    /// The glass ID of the bar itself, for morphing pills to and from it.
    static let glassID = "bar"

    /// How much darker than the raw material the pre-glass bar sits.
    private static let backgroundDim: CGFloat = 0.3

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        surface(content.clipShape(shape))
        // No SwiftUI shadow. Before Liquid Glass the panel's own `hasShadow` drew one
        // from the drawn shapes; on 26+ that is off because the shadow also traced the
        // quick prompt pills and read as a black outline. The glass supplies elevation.
    }

    @ViewBuilder
    private func surface(_ content: some View) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .glassEffectID(Self.glassID, in: glassNamespace)
        } else {
            // A real behind-window vibrancy view, so the bar samples the desktop
            // beneath it the way Spotlight does. The tint sits between the content
            // and the blur, knocking the bar a shade darker than the raw material.
            content
                .background(Color.black.opacity(Self.backgroundDim))
                .background(
                    VisualEffectBackground(
                        material: .hudWindow,
                        blendingMode: .behindWindow,
                        cornerRadius: cornerRadius
                    )
                )
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

/// Groups glass shapes so they blend into one another when close and morph as they
/// appear and disappear. Does nothing before macOS 26.
struct GlassGroup: ViewModifier {
    /// How near two shapes must be before they start to flow together.
    let spacing: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
