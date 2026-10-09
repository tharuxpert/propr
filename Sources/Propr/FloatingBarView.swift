import AppKit
import SwiftUI

/// The actual floating bar UI shown inside the NSPanel.
/// Minimal summon-only design.
struct FloatingBarView: View {
    let snapshot: FieldSnapshot
    @ObservedObject var sessionState: FloatingBarSessionState

    let onRefine: (String) -> Void
    let onStop: () -> Void
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

    private var displayedContextText: String {
        sessionState.latestAppliedText ?? snapshot.contextText
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line of the text being refined. Newlines are flattened so a multi-line
    /// field still previews as a single line; the prefix keeps layout cheap.
    private var textPreview: String {
        String(displayedContextText.prefix(300))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private var statusLabel: String? {
        if sessionState.isThinking { return "Thinking…" }
        if sessionState.isTyping { return "Typing…" }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // One even inset, roughly the corner radius, so the keys in the corners
            // never crowd the rounding.
            sourceStrip
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 12)

            composerRow
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)

            if let error = sessionState.errorMessage {
                RefineErrorBanner(message: error) { sessionState.clearError() }
            }

            if let notice = sessionState.noticeMessage {
                RefineNoticeBanner(message: notice) { sessionState.clearNotice() }
            }
        }
        .frame(maxWidth: .infinity)
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
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .overlay(WorkingEdge(isActive: sessionState.isBusy, cornerRadius: Self.cornerRadius))
        // No SwiftUI shadow: the panel sets `hasShadow`, and now that the content is
        // an opaque rounded shape the window shadow follows it correctly. Drawing
        // both stacked two shadows on top of each other.
    }

    /// Where the text came from and what it is: the source app's icon, then the
    /// captured text as a single quoted line.
    private var sourceStrip: some View {
        HStack(spacing: 9) {
            Image(nsImage: appIcon(for: snapshot.pid))
                .resizable()
                .frame(width: 18, height: 18)
                .help(snapshot.appName)

            if textPreview.isEmpty {
                Text(snapshot.appName == "—" ? "Writing at the cursor" : "Writing in \(snapshot.appName)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The accent rule marks this line as the text being worked on.
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 14)

                Text(textPreview)
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

    /// The instruction field with its key: ↩ to send, or a stop key while busy.
    /// Once a result has been applied, a turn arrow marks the field as a follow-up.
    private var composerRow: some View {
        HStack(spacing: 10) {
            if sessionState.hasAppliedResult {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .help("Follow-up to the last change")
            }

            TextField(promptPlaceholder, text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isPromptFocused)
                .onSubmit {
                    submitPrompt()
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

            if let statusLabel {
                Text(statusLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if sessionState.hasAppliedResult && !sessionState.isBusy, let onUndo {
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(KeycapButtonStyle())
                .help("Undo the last change")
            }

            if sessionState.isBusy {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(KeycapButtonStyle())
                .help("Stop")
            } else {
                Button(action: submitPrompt) {
                    Image(systemName: "return")
                }
                .buttonStyle(KeycapButtonStyle(tint: trimmedPrompt.isEmpty ? nil : .accentColor))
                .disabled(trimmedPrompt.isEmpty)
                .help("Send")
            }
        }
        .animation(.easeOut(duration: 0.15), value: sessionState.isBusy)
    }

    /// Matches the rounding macOS uses on floating panels of this size.
    private static let cornerRadius: CGFloat = 16

    private func submitPrompt() {
        guard !trimmedPrompt.isEmpty, !sessionState.isBusy else { return }
        sessionState.startRequest()
        onRefine(trimmedPrompt)
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
            role: kAXTextAreaRole as String
        ),
        sessionState: FloatingBarSessionState(),
        onRefine: { _ in },
        onStop: {},
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
