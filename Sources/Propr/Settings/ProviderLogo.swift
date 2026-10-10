import SwiftUI

/// A provider's real logo, fetched from its own site, on a light tile so dark
/// glyphs stay visible in dark mode. Falls back to a lettered badge while loading,
/// for local endpoints, and for sites that offer no usable icon.
struct ProviderLogo: View {
    let name: String
    let baseURL: String
    var size: CGFloat = 28

    @State private var icon: NSImage?
    @State private var isFullBleed = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(isFullBleed ? 0 : size * 0.14)
                    .frame(width: size, height: size)
                    .background(shape.fill(.white))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            } else {
                letterBadge
            }
        }
        .accessibilityHidden(true)
        .task(id: baseURL) {
            var loaded = ProviderIconStore.shared.cachedIcon(for: baseURL)
            if loaded == nil {
                loaded = await ProviderIconStore.shared.icon(for: baseURL)
            }
            isFullBleed = loaded.map(Self.hasOpaqueCorner) ?? false
            icon = loaded
        }
    }

    /// Icons that bring their own square background (OpenRouter, Groq) fill the
    /// tile instead of sitting framed in white. A glyph on transparency keeps the
    /// padding.
    private static func hasOpaqueCorner(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let inset = max(1, rep.pixelsWide / 16)
        guard let corner = rep.colorAt(x: inset, y: inset) else { return false }
        return corner.alphaComponent > 0.9
    }

    private var letterBadge: some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(badgeColor.gradient))
    }

    /// A stable color per provider name, so a provider keeps its badge across launches.
    private var badgeColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .red]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
