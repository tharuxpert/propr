import SwiftUI
import AppKit

enum QuickAction: String, CaseIterable, Identifiable {
    case shorter = "Shorter"
    case professional = "Professional"
    case casual = "Casual"
    case fixGrammar = "Fix grammar"
    case bullets = "Bullets"

    var id: String { rawValue }

    var defaultContext: String {
        switch self {
        case .shorter: "Make this shorter and more concise"
        case .professional: "Rewrite this in a professional tone"
        case .casual: "Make this sound casual and friendly"
        case .fixGrammar: "Fix any grammar or spelling issues"
        case .bullets: "Turn this into clear bullet points"
        }
    }

    var systemImage: String {
        switch self {
        case .shorter: "text.line.first.and.arrowtriangle.forward"
        case .professional: "briefcase"
        case .casual: "face.smiling"
        case .fixGrammar: "checkmark.bubble"
        case .bullets: "list.bullet"
        }
    }
}

/// The actual floating bar UI shown inside the NSPanel.
/// Minimal summon-only design.
struct FloatingBarView: View {
    let snapshot: FieldSnapshot

    let onQuickAction: (QuickAction) -> Void   // kept for signature compatibility (unused now)
    let onRefine: (String) -> Void
    let onClose: () -> Void
    var onUndo: (() -> Void)? = nil

    @State private var prompt: String = ""
    @FocusState private var isPromptFocused: Bool
    @State private var hasApplied = false
    @State private var lastPrompt: String = ""

    private var textPreview: String {
        let text = snapshot.selectedText?.isEmpty == false ? snapshot.selectedText! : snapshot.fullText
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
                        lastPrompt = trimmed
                        hasApplied = true
                        onRefine(trimmed)
                    }
                }
                .onAppear {
                    // Auto-focus the input as soon as the bar appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isPromptFocused = true
                    }
                }
                .disabled(hasApplied)

            if hasApplied {
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
            fullText: "This is some text I wrote quickly and now I want to make it sound better for a blog post or an important email to my team.",
            selectedText: nil,
            frame: .zero,
            role: kAXTextAreaRole as String
        ),
        onQuickAction: { _ in },
        onRefine: { _ in },
        onClose: {}
    )
    .padding(40)
    .background(Color.black.opacity(0.6))
}
