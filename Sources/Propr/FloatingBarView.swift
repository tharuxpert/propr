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
struct FloatingBarView: View {
    let snapshot: FieldSnapshot

    let onQuickAction: (QuickAction) -> Void
    let onRefine: (String) -> Void
    let onClose: () -> Void

    @State private var contextText: String = "Make this clearer and more concise"

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: app badge + count + close
            HStack(spacing: 8) {
                // App source
                HStack(spacing: 6) {
                    Image(nsImage: appIcon(for: snapshot.pid))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text(snapshot.appName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Character count
                Text("\(snapshot.characterCount) chars")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    )

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(.quaternary.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.4)

            // Context / instruction field
            VStack(alignment: .leading, spacing: 6) {
                Text("Context")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                TextField("What should the rewrite do?", text: $contextText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickAction.allCases) { action in
                        Button {
                            onQuickAction(action)
                        } label: {
                            Label(action.rawValue, systemImage: action.systemImage)
                                .font(.caption.weight(.medium))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.secondary)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 8)

            // Refine button
            Button {
                onRefine(contextText)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Refine")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)

            // Subtle footer note (temporary until real AI)
            Text("Local simulation • real AI coming soon")
                .font(.caption2)
                .foregroundStyle(.tertiary.opacity(0.7))
                .padding(.bottom, 6)
        }
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear {
            // Seed a reasonable context from the snapshot if the user hasn't customized
            if contextText == "Make this clearer and more concise" && !snapshot.fullText.isEmpty {
                // Leave the default — it's good. Could auto-adapt later.
            }
        }
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
