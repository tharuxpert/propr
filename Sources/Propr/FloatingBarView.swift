import AppKit
import SwiftUI

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

    /// Asking "what do you want to do with this text?" when no text was captured
    /// points at nothing. With an empty context the bar writes at the cursor instead,
    /// so the prompt asks for that.
    private var promptPlaceholder: String {
        if sessionState.hasAppliedResult {
            return "What should change next?"
        }

        return snapshot.contextText.isEmpty
            ? "What do you want to write?"
            : "What do you want to do with this text?"
    }

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
                HStack(spacing: 8) {
                    Image(nsImage: appIcon(for: snapshot.pid))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if snapshot.appName != "—" {
                        Text(snapshot.appName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if snapshot.characterCount > 0 {
                    Text("\(snapshot.characterCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.25)

            // Truncated preview of the text being refined (not the whole thing)
            if !textPreview.isEmpty {
                Text(textPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .opacity(0.2)
            }

            // Main instruction input. Once a result has been applied, make the
            // ongoing conversation explicit instead of presenting a fresh composer.
            VStack(alignment: .leading, spacing: 6) {
                if sessionState.hasAppliedResult {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                        Text("Follow-up")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                }

                TextField(promptPlaceholder, text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isPromptFocused)
                    .onSubmit {
                        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !sessionState.isBusy {
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
                    .onChange(of: sessionState.composerRevision) {
                        prompt = ""
                        DispatchQueue.main.async {
                            isPromptFocused = true
                        }
                    }
                    .disabled(sessionState.isBusy)
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

            if sessionState.isThinking {
                RefineStatusRow(label: "Thinking…")
            } else if sessionState.isTyping {
                RefineStatusRow(label: "Typing…")
            }

            if let error = sessionState.errorMessage {
                RefineErrorBanner(message: error) { sessionState.clearError() }
            }

            if let notice = sessionState.noticeMessage {
                RefineNoticeBanner(message: notice) { sessionState.clearNotice() }
            }

            if sessionState.hasAppliedResult && !sessionState.isBusy {
                HStack(spacing: 12) {
                    if let onUndo {
                        Button("Undo", action: onUndo)
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    }

                    Spacer()

                    Button("Done") {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 470)
        .modifier(DraggablePanel())
        // A real behind-window vibrancy view, so the bar samples the desktop beneath
        // it the way Spotlight does. The panel itself is borderless and clear; the
        // rounding and the shadow live here.
        .background(
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: Self.cornerRadius
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            // The hairline macOS puts around floating panels: a light top edge over a
            // separator, rather than a uniform white stroke.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        // No SwiftUI shadow: the panel sets `hasShadow`, and now that the content is
        // an opaque rounded shape the window shadow follows it correctly. Drawing
        // both stacked two shadows on top of each other.
    }

    /// Matches the rounding macOS uses on floating panels of this size.
    private static let cornerRadius: CGFloat = 12

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
            role: kAXTextAreaRole as String
        ),
        sessionState: FloatingBarSessionState(),
        onRefine: { _ in },
        onClose: {}
    )
    .padding(40)
    .background(Color.black.opacity(0.6))
}

/// Lets the bar be dragged around by any part that is not a control.
///
/// SwiftUI content does not reliably take part in AppKit's
/// `isMovableByWindowBackground`, which is all the bar relied on. From macOS 15 the
/// documented way to drag a window by a SwiftUI view is `WindowDragGesture`, and
/// `allowsWindowActivationEvents()` is what lets that work on a window whose app is
/// not active — which, for this non-activating panel, is always.
///
/// It sits on the whole bar so the header (icon and app name) drags too. The text
/// field keeps selecting text normally: it is an AppKit field that handles its own
/// mouse events before SwiftUI gestures see them. A plain click on a button still
/// goes to the button, since a child's tap outranks a parent's drag.
///
/// On macOS 14 the panel's `isMovableByWindowBackground` remains the only path.
private struct DraggablePanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                // Without this SwiftUI only hit-tests actual child views, so padding
                // and the header's Spacer — the blank areas you would naturally grab —
                // would not start a drag.
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents()
        } else {
            content
        }
    }
}
