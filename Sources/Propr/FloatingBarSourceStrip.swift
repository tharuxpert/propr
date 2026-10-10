import AppKit
import SwiftUI

/// The bar's top line: where the text came from and what it is — the source app's
/// icon, then the captured text as a single quoted line — with the close key.
struct FloatingBarSourceStrip: View {
    let appName: String
    let pid: pid_t
    /// One line of the text being worked on; empty when nothing was captured.
    let preview: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 18, height: 18)
                .help(appName)

            if preview.isEmpty {
                Text(appName == "—" ? "Writing at the cursor" : "Writing in \(appName)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The accent rule marks this line as the text being worked on.
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 14)

                Text(preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("esc", action: onClose)
                .buttonStyle(KeycapButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close")
        }
        .font(.callout)
    }

    private var appIcon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
