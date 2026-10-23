import SwiftUI

/// Edits the quick prompts the bar offers as pills: the text of each, whether it
/// asks or edits, and their order. Drag a row to reorder it.
struct QuickPromptsEditor: View {
    @Binding var prompts: QuickPrompts

    /// Height of one row, used to size the list to its content: a list inside the
    /// scrolling pane cannot size itself.
    private static let rowHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach($prompts.items) { $prompt in
                    row($prompt)
                }
                .onMove { source, destination in
                    prompts.items.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: max(1, CGFloat(prompts.items.count)) * Self.rowHeight + 6)

            HStack(spacing: 12) {
                Button("Add Prompt", action: addPrompt)
                    .disabled(!prompts.canAdd)
                Button("Restore Defaults") { prompts = .defaults }
                    .disabled(prompts == .defaults)
            }

            SettingsNote(
                "Shown under the bar while it has text and you haven't typed. "
                    + "Ask answers in the bar; Edit changes your text. ⌘1–⌘\(QuickPrompts.limit) send them."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ prompt: Binding<QuickPrompt>) -> some View {
        HStack(spacing: 10) {
            TextField("Prompt", text: prompt.text, prompt: Text("e.g. Translate to French"))
                .textFieldStyle(.plain)
                .onChange(of: prompt.wrappedValue.text) { _, newValue in
                    if newValue.count > QuickPrompts.textLimit {
                        prompt.wrappedValue.text = String(newValue.prefix(QuickPrompts.textLimit))
                    }
                }

            Picker("Mode", selection: prompt.mode) {
                ForEach(QuickPrompt.Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            Button {
                prompts.items.removeAll { $0.id == prompt.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .frame(minHeight: Self.rowHeight - 8)
    }

    private func addPrompt() {
        guard prompts.canAdd else { return }
        prompts.items.append(QuickPrompt(text: "", mode: .ask))
    }
}

#Preview {
    @Previewable @State var prompts = QuickPrompts.defaults
    QuickPromptsEditor(prompts: $prompts)
        .padding()
        .frame(width: 460)
}
