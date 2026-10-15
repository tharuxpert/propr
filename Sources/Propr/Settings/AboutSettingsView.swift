import SwiftUI

/// The About pane: the app's identity and version, with links out to the project.
/// Kept apart from General so that pane holds only settings.
struct AboutSettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/tharuxpert/propr")!
    private static let issuesURL = URL(string: "https://github.com/tharuxpert/propr/issues/new")!

    @Environment(\.openURL) private var openURL

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, build != short else {
            return "Version \(short)"
        }
        return "Version \(short) (\(build))"
    }

    private var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Propr")
                        .font(.title.weight(.semibold))
                    Text(version)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Refine or look up any text, right where you are.")
                        .foregroundStyle(.secondary)
                    if let copyright {
                        Text(copyright)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                Button("View on GitHub") { openURL(Self.repositoryURL) }
                Button("Send Feedback") { openURL(Self.issuesURL) }
            }
            .padding(20)
        }
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 780, height: 560)
}
