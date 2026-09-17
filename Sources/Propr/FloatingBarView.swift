import AppKit
import SwiftUI

@MainActor
final class FloatingBarSessionState: ObservableObject {
    @Published var hasSubmitted = false
    @Published var isThinking = false
    @Published var isTyping = false
    @Published var errorMessage: String?

    func startRequest() {
        hasSubmitted = true
        isThinking = true
        isTyping = false
        errorMessage = nil
    }

    func startTyping() {
        isThinking = false
        isTyping = true
    }

    func finishRequest() {
        isThinking = false
        isTyping = false
    }

    func stopTyping() {
        isTyping = false
    }

    func fail(_ message: String) {
        hasSubmitted = false
        isThinking = false
        isTyping = false
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}

/// The actual floating bar UI shown inside the NSPanel.
/// Minimal summon-only design.
struct FloatingBarView: View {
    let snapshot: FieldSnapshot
    @ObservedObject var sessionState: FloatingBarSessionState

    let onRefine: (String) -> Void
    let onClose: () -> Void
    var onUndo: (() -> Void)? = nil

    @State private var prompt: String = ""
    @FocusState private var isPromptFocused: Bool

    private var textPreview: String {
        let text =
            snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : snapshot.fullText
        let maxLength = 110
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            // Minimal top bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(nsImage: appIcon(for: snapshot.pid))
                        .resizable()
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    if snapshot.appName != "—" {
                        Text(snapshot.appName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if snapshot.characterCount > 0 {
                    Text("\(snapshot.characterCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .opacity(0.25)

            // Truncated preview of the text being refined (not the whole thing)
            if !textPreview.isEmpty {
                Text(textPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .opacity(0.2)
            }

            // Main instruction input
            TextField("What do you want to do with this text?", text: $prompt)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .focused($isPromptFocused)
                .onSubmit {
                    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sessionState.startRequest()
                        onRefine(trimmed)
                    }
                }
                .onAppear {
                    // Auto-focus the input as soon as the bar appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isPromptFocused = true
                    }
                }
                .disabled(sessionState.hasSubmitted && sessionState.errorMessage == nil)

            if sessionState.isThinking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else if sessionState.isTyping {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Typing…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if let error = sessionState.errorMessage {
                // The message wraps instead of truncating: a provider error is the
                // one thing here the user cannot act on without reading it in full.
                // It is selectable so it can be copied into a search or bug report.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text(error)
                            .font(.callout)
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
                            NSPasteboard.general.setString(error, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Dismiss") {
                            sessionState.clearError()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
            }

            if sessionState.hasSubmitted && !sessionState.isThinking && !sessionState.isTyping
                && sessionState.errorMessage == nil
            {
                HStack(spacing: 12) {
                    if let onUndo {
                        Button("Undo", action: onUndo)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Spacer()

                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func appIcon(for pid: pid_t) -> NSImage {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

#Preview("Floating Bar") {
    FloatingBarView(
        snapshot: FieldSnapshot(
            appName: "Notes",
            pid: 1234,
            fullText:
                "This is some text I wrote quickly and now I want to make it sound better for a blog post or an important email to my team.",
            selectedText: nil,
            frame: .zero,
            role: kAXTextAreaRole as String
        ),
        sessionState: FloatingBarSessionState(),
        onRefine: { _ in },
        onClose: {}
    )
    .padding(40)
    .background(Color.black.opacity(0.6))
}
