import SwiftUI

/// A white symbol on a colored rounded square, the badge System Settings puts in
/// front of every pane and row. Gives each setting a recognizable shape instead of a
/// wall of identical text rows.
struct SettingsIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

/// A settings row label with its badge, for use as a `Toggle` or `LabeledContent`
/// label so the control stays trailing-aligned.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: systemImage, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A badged row with its control vertically centered on the trailing edge.
///
/// `LabeledContent` and `Toggle` align the control with the label's first line,
/// which leaves it sitting high once the label gains a subtitle.
struct SettingsRow<Control: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    var subtitle: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowLabel(title: title, systemImage: systemImage, color: color, subtitle: subtitle)
            Spacer(minLength: 8)
            control
        }
    }
}

/// A static key, drawn like the keycaps in the floating bar, for showing a shortcut.
struct SettingsKeycap: View {
    let symbol: String

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 22, minHeight: 20)
            .background(shape.fill(Color.primary.opacity(0.08)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
    }
}

#Preview {
    Form {
        LabeledContent {
            HStack(spacing: 4) {
                SettingsKeycap(symbol: "⌘")
                SettingsKeycap(symbol: "⌘")
            }
        } label: {
            SettingsRowLabel(title: "Shortcut", systemImage: "command", color: .blue)
        }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 120)
}
