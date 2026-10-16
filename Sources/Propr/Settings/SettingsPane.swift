import SwiftUI

/// The frame every Settings pane sits in: a scrolling column of fixed width,
/// centred in the window, the way Mac settings windows keep a wide window readable.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                content
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A pane's settings: SwiftUI's columns form, which right-aligns each label in a
/// leading column and lines the controls up in a trailing one.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.columns)
    }
}

/// One labelled row of a `SettingsForm`, with breathing room above and below so
/// neighbouring settings read as separate.
struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        // The trailing colon is the Mac settings convention, so callers pass the
        // plain label and every row gets one.
        LabeledContent("\(title):") {
            content
        }
        .padding(.vertical, 8)
    }
}

/// Secondary explanation under a control, wrapping within the control column.
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
    SettingsPane {
        SettingsForm {
            SettingsRow("Shortcut") {
                HStack(spacing: 4) {
                    SettingsKeycap(symbol: "⌘")
                    SettingsKeycap(symbol: "⌘")
                }
            }
        }
    }
    .frame(width: 720, height: 200)
}
