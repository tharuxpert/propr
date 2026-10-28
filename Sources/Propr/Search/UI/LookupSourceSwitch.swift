import SwiftUI

/// What the Lookup panel's source switch shows, and who hears about a change.
/// Kept apart from the view so the AppKit panel can set the selection when it opens
/// without that counting as the user switching.
@MainActor
@Observable
final class LookupSourceModel {
    var selection: SearchProvider
    @ObservationIgnored var onSelect: ((SearchProvider) -> Void)?

    init(selection: SearchProvider) {
        self.selection = selection
    }
}

/// The Lookup panel's Google / AI switch: a glass thumb that slides between the
/// sources with a spring.
///
/// Custom because the system segmented control's selection snapped rather than slid
/// in this panel.
struct LookupSourceSwitch: View {
    let model: LookupSourceModel

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SearchProvider.allCases, id: \.self) { provider in
                segment(provider)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .fixedSize()
    }

    private func segment(_ provider: SearchProvider) -> some View {
        let isSelected = model.selection == provider

        return Button {
            guard !isSelected else { return }
            // Animated here rather than on every change, so the panel resetting the
            // source as it opens does not play a slide.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                model.selection = provider
            }
            model.onSelect?(provider)
        } label: {
            Text(provider.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .frame(height: 24)
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        SwitchThumb()
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// The selected source's capsule: Liquid Glass from macOS 26, a light fill before it.
private struct SwitchThumb: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(Color.primary.opacity(0.16))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
        }
    }
}
