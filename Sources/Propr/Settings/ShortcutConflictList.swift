import AppKit
import SwiftUI

/// The current shortcut conflicts, re-checked whenever Propr becomes active, so
/// changing the setting in System Settings and switching back clears a warning
/// without reopening anything.
@MainActor
@Observable
final class ShortcutConflictMonitor {
    static let shared = ShortcutConflictMonitor()

    private(set) var conflicts = ShortcutConflictDetector.current()

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ShortcutConflictMonitor.shared.refresh() }
        }
    }

    func refresh() {
        let latest = ShortcutConflictDetector.current()
        if latest != conflicts { conflicts = latest }
    }
}

/// Lists shortcut conflicts with the fix for each and a link to the right System
/// Settings pane.
struct ShortcutConflictList: View {
    let conflicts: [ShortcutConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(conflicts) { conflict in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(conflict.title)
                            .font(.callout.weight(.medium))
                        Text(conflict.fix)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button("Open…") { NSWorkspace.shared.open(conflict.settingsPaneURL) }
                        .controlSize(.small)
                        .help("Open the System Settings pane for this shortcut")
                }
            }
        }
    }
}
