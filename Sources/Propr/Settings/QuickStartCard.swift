import SwiftUI

/// One provider tile in the Quick Start grid.
///
/// Kept deliberately stateless — the grid is non-lazy because a LazyVGrid above a
/// form whose height changes was dropping cells during fast scroll.
struct QuickStartCard: View {
    let provider: BuiltInProvider
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.subheadline.weight(.medium))
                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickStartCard(provider: BuiltInProvider.all[0], action: {})
        .frame(width: 200)
        .padding()
}
