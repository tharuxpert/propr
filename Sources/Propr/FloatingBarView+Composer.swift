import SwiftUI

// The composer row: the mode key, the instruction field and its keys.
extension FloatingBarView {
    /// With text captured the bar can edit it or answer about it, so the fresh
    /// prompt stays open-ended. With an empty context the bar writes at the cursor
    /// instead, so the prompt asks for that.
    private var promptPlaceholder: String {
        // A stamp is landing where the placeholder would be.
        if quickPromptStamp != nil { return "" }
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

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusLabel: String? {
        if sessionState.isThinking { return "Thinking…" }
        if sessionState.isTyping { return "Typing…" }
        return nil
    }

    /// The instruction field with its key: ↩ to send, or a stop key while busy.
    /// The leading icon shows the mode and toggles it, like Tab: a question bubble
    /// for Ask, a turn arrow for a follow-up edit, a pencil for a first edit.
    var composerRow: some View {
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
                .font(.system(size: QuickPromptStamp.composerFontSize))
                .focused($isPromptFocused)
                // Where a quick prompt's stamp lands.
                .onGeometryChange(for: CGPoint?.self) { proxy in
                    QuickPromptStamp.textOrigin(
                        of: proxy.frame(in: .named(QuickPromptStamp.stage)), inset: 0)
                } action: { origin in
                    if let origin { promptTextOrigin = origin }
                }
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
            if prompt.isEmpty && quickPromptStamp == nil && !sessionState.isBusy {
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
