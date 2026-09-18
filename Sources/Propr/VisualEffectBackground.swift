import AppKit
import SwiftUI

/// A real `NSVisualEffectView` behind SwiftUI content.
///
/// SwiftUI's `.ultraThinMaterial` blends against what is *inside* the window. For a
/// floating panel over other applications, the blur has to sample the desktop behind
/// it — that needs `blendingMode = .behindWindow`, which only AppKit exposes. Without
/// it the bar looks like a flat translucent rectangle rather than a Mac panel.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // Keep the blur live while the panel is not the active window, which it often
        // is not — the whole point is that it floats over someone else's app.
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
    }
}
