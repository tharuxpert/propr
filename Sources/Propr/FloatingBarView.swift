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
    /// Reports the content's natural height whenever it changes, so the panel can
    /// be sized to it. SwiftUI measures it; the panel does not size itself.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    @State var prompt: String = ""
    @FocusState private var isPromptFocused: Bool
    @Namespace var glassNamespace
    @AppStorage(QuickPrompts.key) var quickPrompts = QuickPrompts.defaults
    /// Keeps the pills' space for a moment after they hide, so the panel does not
    /// shrink under them while they flow back into the bar.
    @State var holdsQuickPromptSpace = false
    /// Whether the pills are out. Trails `showsQuickPrompts` on the way in, until
    /// the panel has grown to make room for them.
    @State var revealsQuickPrompts = false

    /// With text captured the bar can edit it or answer about it, so the fresh
    /// prompt stays open-ended. With an empty context the bar writes at the cursor
    /// instead, so the prompt asks for that.
    private var promptPlaceholder: String {
        if sessionState.isAskMode {
            // The source strip above already shows the captured text, so the
            // prompt needn't point at it.
            return "Ask anything…"
        }
        if sessionState.hasAppliedResult {
            return "What should change next?"
        }

        return snapshot.contextText.isEmpty
            ? "What do you want to write?"
            : "Ask or edit anything…"
    }

    var displayedContextText: String {
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
            bar
            // Animated on its own, so the pills' spring never slows the rest of the
            // bar: the placeholder and the tab hint still change at once.
            quickPromptArea
        }
        .modifier(GlassGroup(spacing: Self.glassBlendSpacing))
        // Natural height, whatever frame the panel currently has.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            onContentHeightChange?(height)
        }
        // Pinned to the top. The panel catches up with a change in height a pass
        // later, and until then the hosting view would centre the content in the
        // old frame, jumping the bar up and back down.
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            holdsQuickPromptSpace = showsQuickPrompts
            revealsQuickPrompts = showsQuickPrompts
        }
        .onChange(of: showsQuickPrompts) { _, shows in
            quickPromptVisibilityChanged(to: shows)
        }
    }

    /// The bar itself: the source strip, the composer and whatever the last request
    /// produced.
    private var bar: some View {
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
        // The panel itself is borderless and clear; the backdrop and rounding live here.
        .modifier(
            FloatingBarSurface(
                cornerRadius: Self.cornerRadius,
                isBusy: sessionState.isBusy,
                glassNamespace: glassNamespace
            )
        )
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

    /// How near the pills and the bar must be before their glass flows together.
    /// Narrower than the gap between them, so they merge only while moving in and
    /// out; at rest the bar's own shape stays exactly as it is.
    private static let glassBlendSpacing: CGFloat = 6

    private func submitPrompt() {
        guard !trimmedPrompt.isEmpty else { return }
        send(trimmedPrompt, intent: sessionState.isAskMode ? .ask : .auto)
    }

    func send(_ instruction: String, intent: RefineIntent) {
        guard !sessionState.isBusy else { return }
        sessionState.startRequest()
        onRefine(instruction, intent)
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
