import SwiftUI

/// A small key-shaped button.
///
/// The bar is summoned and driven from the keyboard, so its controls are drawn as
/// the keys that trigger them: ↩ sends, esc closes. Each one is a hint and a button.
struct KeycapButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        Keycap(label: configuration.label, tint: tint, isPressed: configuration.isPressed)
    }

    private struct Keycap<Label: View>: View {
        let label: Label
        let tint: Color?
        let isPressed: Bool

        @Environment(\.isEnabled) private var isEnabled

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        }

        var body: some View {
            label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .padding(.horizontal, 6)
                .frame(minWidth: 24, minHeight: 21)
                .background(shape.fill(tint ?? Color.primary.opacity(0.09)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                // The lip along the bottom edge that makes it read as a key; it
                // flattens when pressed, as a real key would.
                .shadow(color: .black.opacity(isPressed ? 0 : 0.4), radius: 0, y: 1)
                .offset(y: isPressed ? 1 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
                .animation(.easeOut(duration: 0.12), value: tint)
        }
    }
}

/// The quiet "tab Ask" hint in an empty composer: names the mode Tab switches to,
/// since nothing else says Tab does anything. Clicking it switches too.
struct ModeSwitchHint: View {
    /// The mode Tab would switch to, such as "Ask".
    let target: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("tab")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 4)
                    .frame(minHeight: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
                Text(target)
                    .font(.callout)
            }
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Press Tab to switch to \(target)")
    }
}

/// A light streak that travels around the bar's edge while a request is running.
///
/// The bar's one moment of motion, and it only plays while Propr is actually
/// working, so it doubles as the busy indicator. With Reduce Motion it holds still.
struct WorkingEdge: View {
    let isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one lap of the edge.
    private static let lapDuration: TimeInterval = 2.2

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { timeline in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let gradient = streak(at: angle(at: timeline.date))

            ZStack {
                // A touch heavier than on the old vibrancy, so it holds its own
                // against the glass's bright rim.
                shape.strokeBorder(gradient, lineWidth: 4).blur(radius: 4).opacity(0.85)
                shape.strokeBorder(gradient, lineWidth: 1.75)
            }
            // The glow may only spill inward. Anything drawn outside the rounded
            // shape fills the window's corners, and the window shadow turns square.
            .clipShape(shape)
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: isActive)
        .allowsHitTesting(false)
    }

    private func angle(at date: Date) -> Angle {
        guard !reduceMotion else { return .degrees(-90) }
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Self.lapDuration) / Self.lapDuration
        return .degrees(progress * 360)
    }

    private func streak(at angle: Angle) -> AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .accentColor.opacity(0), location: 0),
                .init(color: .accentColor.opacity(0), location: 0.7),
                .init(color: .accentColor, location: 0.92),
                .init(color: .white, location: 0.97),
                .init(color: .accentColor.opacity(0), location: 1),
            ],
            center: .center,
            angle: angle
        )
    }
}

/// Lets the bar be dragged around by any part that is not a control.
///
/// SwiftUI content does not reliably take part in AppKit's
/// `isMovableByWindowBackground`, which is all the bar relied on. From macOS 15 the
/// documented way to drag a window by a SwiftUI view is `WindowDragGesture`, and
/// `allowsWindowActivationEvents()` is what lets that work on a window whose app is
/// not active — which, for this non-activating panel, is always.
///
/// It sits on the whole bar so the header (icon and app name) drags too. The text
/// field keeps selecting text normally: it is an AppKit field that handles its own
/// mouse events before SwiftUI gestures see them. A plain click on a button still
/// goes to the button, since a child's tap outranks a parent's drag.
///
/// On macOS 14 the panel's `isMovableByWindowBackground` remains the only path.
struct DraggablePanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                // Without this SwiftUI only hit-tests actual child views, so padding
                // and the header's Spacer — the blank areas you would naturally grab —
                // would not start a drag.
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents()
        } else {
            content
        }
    }
}

#Preview("Keycaps") {
    HStack(spacing: 8) {
        Button("esc") {}.buttonStyle(KeycapButtonStyle())
        Button {} label: { Image(systemName: "return") }
            .buttonStyle(KeycapButtonStyle(tint: .accentColor))
        Button {} label: { Image(systemName: "return") }
            .buttonStyle(KeycapButtonStyle())
            .disabled(true)
    }
    .padding(30)
}
