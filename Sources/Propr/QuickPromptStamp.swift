import SwiftUI

/// A quick prompt on its way from its pill into the composer, where it is stamped
/// down before being sent.
struct QuickPromptStamp: Equatable, Identifiable {
    let id = UUID()
    let text: String
    /// Where the text starts and lands, in the bar's stage coordinates.
    let start: CGPoint
    let landing: CGPoint

    /// The coordinate space both ends are measured in.
    static let stage = "floatingBarStage"

    /// When the text hits the composer, from the click.
    static let landingDelay: Duration = .milliseconds(300)
    /// How long the stamp is left to settle before the prompt is sent.
    static let settleDelay: Duration = .milliseconds(220)

    /// Where text starts in `frame`: its leading edge, `inset` in, at its vertical
    /// centre. Nil for an empty frame.
    ///
    /// Just after the bar appears, SwiftUI passes through a layout in which every
    /// pill has an empty frame. Taken at face value it put each pill at the top of
    /// the bar, and since the pills then sat still nothing corrected it, so the
    /// first stamp flew in from there.
    static func textOrigin(of frame: CGRect, inset: CGFloat) -> CGPoint? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return CGPoint(x: frame.minX + inset, y: frame.midY)
    }

    /// The pill's text and the composer's are drawn at these sizes.
    static let pillFontSize: CGFloat = 12
    static let composerFontSize: CGFloat = 16
}

/// The stamp's text in flight: it lifts off the pill, swells as it travels up to
/// the composer, then slams down to the composer's own size with a bounce.
struct QuickPromptStampFlight: View {
    let stamp: QuickPromptStamp

    @State private var isFlying = false

    private struct Pose {
        /// 0 at the pill, 1 in the composer.
        var travel: CGFloat = 0
        var scale: CGFloat = QuickPromptStamp.pillFontSize / QuickPromptStamp.composerFontSize
    }

    /// Room for one line of composer text, so the text can be placed by its
    /// vertical centre.
    private static let lineHeight: CGFloat = 22

    var body: some View {
        // Copied out: the animator's closure runs off the main actor.
        let start = stamp.start
        let landing = stamp.landing
        let lineHeight = Self.lineHeight

        Text(stamp.text)
            .font(.system(size: QuickPromptStamp.composerFontSize))
            .lineLimit(1)
            .fixedSize()
            .keyframeAnimator(initialValue: Pose(), trigger: isFlying) { text, pose in
                let x = start.x + (landing.x - start.x) * pose.travel
                let y = start.y + (landing.y - start.y) * pose.travel
                return text
                    .scaleEffect(pose.scale, anchor: .leading)
                    .frame(height: lineHeight, alignment: .leading)
                    .offset(x: x, y: y - lineHeight / 2)
            } keyframes: { _ in
                KeyframeTrack(\.travel) {
                    // Arrives exactly as the slam starts. A spring here was still
                    // short of the composer when it slammed, landing low by a share
                    // of the distance, which grew the further down the pills sat.
                    LinearKeyframe(1, duration: 0.26, timingCurve: .easeInOut)
                }
                KeyframeTrack(\.scale) {
                    // Swells on the way up, as if lifted towards you…
                    CubicKeyframe(1.7, duration: 0.26)
                    // …then slams past its size and bounces back to it.
                    CubicKeyframe(0.9, duration: 0.06)
                    SpringKeyframe(1, duration: 0.24, spring: .bouncy(duration: 0.24, extraBounce: 0.2))
                }
            }
            .allowsHitTesting(false)
            .onAppear { isFlying = true }
    }
}
