import AppKit
import SwiftUI

/// The actual floating bar UI shown inside the NSPanel.
/// Minimal summon-only design.
struct FloatingBarView: View {
    let snapshot: FieldSnapshot
    @ObservedObject var sessionState: FloatingBarSessionState

    let onRefine: (String, RefineIntent) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    var onUndo: (() -> Void)? = nil

    @State private var prompt: String = ""
    @FocusState private var isPromptFocused: Bool

    /// Asking "what do you want to do with this text?" when no text was captured
    /// points at nothing. With an empty context the bar writes at the cursor instead,
    /// so the prompt asks for that.
    private var promptPlaceholder: String {
        if sessionState.isAskMode {
            return snapshot.contextText.isEmpty ? "Ask anything" : "Ask about this text"
        }
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
            FloatingBarSourceStrip(
                appName: snapshot.appName,
                pid: snapshot.pid,
                preview: textPreview,
                onClose: onClose
            )
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 12)

            composerRow
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)

            if let answer = sessionState.answer {
                AnswerSection(answer: answer)
            }

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
        //
        // The tint sits between the content and the blur, knocking the whole
        // composer a shade darker than the raw material.
        .background(Color.black.opacity(Self.backgroundDim))
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

    /// The instruction field with its key: ↩ to send, or a stop key while busy.
    /// The leading icon shows the mode and toggles it, like Tab: a question bubble
    /// for Ask, a turn arrow for a follow-up edit, a pencil for a first edit.
    private var composerRow: some View {
        HStack(spacing: 10) {
            Button(action: toggleAskMode) {
                Image(systemName: modeSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(sessionState.isBusy)
            .help(
                sessionState.isAskMode
                    ? "Ask: answers stay here and nothing in your text changes. Tab switches to Edit."
                    : "Edit: changes your text. Tab switches to Ask."
            )

            TextField(promptPlaceholder, text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isPromptFocused)
                .onKeyPress(.tab) {
                    toggleAskMode()
                    return .handled
                }
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

            // Gone once typing starts, so it never crowds a real instruction.
            if prompt.isEmpty && !sessionState.isBusy {
                ModeSwitchHint(
                    target: sessionState.isAskMode ? "Edit" : "Ask",
                    action: toggleAskMode
                )
                .transition(.opacity)
            }

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

    /// How much darker than the raw material the composer sits.
    private static let backgroundDim: CGFloat = 0.3

    private func submitPrompt() {
        guard !trimmedPrompt.isEmpty, !sessionState.isBusy else { return }
        sessionState.startRequest()
        onRefine(trimmedPrompt, sessionState.isAskMode ? .ask : .auto)
    }

    private var modeSymbol: String {
        if sessionState.isAskMode { return "questionmark.bubble" }
        return sessionState.hasAppliedResult ? "arrow.turn.down.right" : "pencil.line"
    }

    private func toggleAskMode() {
        guard !sessionState.isBusy else { return }
        sessionState.isAskMode.toggle()
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
        onRefine: { _, _ in },
        onStop: {},
        onClose: {}
    )
    .padding(40)
    .background(Color.black.opacity(0.6))
}
