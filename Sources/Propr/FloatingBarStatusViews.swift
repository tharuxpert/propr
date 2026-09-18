import AppKit
import SwiftUI

/// The spinner + label shown while a refine is in flight.
///
/// One view rather than two near-identical blocks: "Thinking…" and "Typing…" differ
/// only in their label.
struct RefineStatusRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A provider error, shown in full.
///
/// The message wraps rather than truncating — a provider error is the one thing here
/// the user cannot act on without reading all of it — and is selectable and copyable
/// so it can go straight into a search or a bug report.
struct RefineErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }
}

/// A valid model response that was intentionally not written into the document.
///
/// Unlike an error, this means the request completed normally but the model could
/// not produce safe output without guessing or additional information.
struct RefineNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No changes were made")
                        .font(.body.weight(.medium))

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }
}

#Preview("Status") {
    VStack(spacing: 0) {
        RefineStatusRow(label: "Thinking…")
        RefineErrorBanner(
            message: "API error (403): This model requires a verified organization.",
            onDismiss: {}
        )
        RefineNoticeBanner(
            message: "I do not have the vocabulary or grammar of your private language.",
            onDismiss: {}
        )
    }
    .frame(width: 470)
}
