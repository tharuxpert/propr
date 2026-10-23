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
                    SpringKeyframe(1, duration: 0.3, spring: .smooth(duration: 0.3))
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
