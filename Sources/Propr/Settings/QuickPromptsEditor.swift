import SwiftUI

/// Edits the quick prompts the bar offers as pills: the text of each, which of the
/// bar's modes it shows in, and their order. Drag a row to reorder it.
///
/// Laid out like a Mac settings list: plain rows in a box, with + and − beneath.
struct QuickPromptsEditor: View {
    @Binding var prompts: QuickPrompts

    @State private var selection: QuickPrompt.ID?
    @FocusState private var focusedPrompt: QuickPrompt.ID?

    /// Height of one row, used to size the list to its content: a list inside the
    /// scrolling pane cannot size itself.
    private static let rowHeight: CGFloat = 30

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    /// The prompt − removes: the one being typed in, else the selected row.
    private var removable: QuickPrompt.ID? {
        focusedPrompt ?? selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                list
                Divider()
                toolbar
            }
            .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))

            SettingsNote(
                "Shown under the bar before you type. ⌘1–⌘\(QuickPrompts.limit) send them in this order.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var list: some View {
        List(selection: $selection) {
            ForEach($prompts.items) { $prompt in
                row($prompt)
                    .tag(prompt.id)
            }
            .onMove { source, destination in
                prompts.items.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .onDeleteCommand(perform: removeSelected)
        .frame(height: max(1, CGFloat(prompts.items.count)) * Self.rowHeight + 8)
        .overlay {
            if prompts.items.isEmpty {
                Text("No quick prompts")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ prompt: Binding<QuickPrompt>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")

            TextField("Prompt", text: prompt.text, prompt: Text("e.g. Translate to French"))
                .textFieldStyle(.plain)
                .focused($focusedPrompt, equals: prompt.wrappedValue.id)
                .onChange(of: prompt.wrappedValue.text) { _, newValue in
                    if newValue.count > QuickPrompts.textLimit {
                        prompt.wrappedValue.text = String(newValue.prefix(QuickPrompts.textLimit))
                    }
                }

            ModesMenu(modes: prompt.modes)
        }
        .frame(height: Self.rowHeight - 8)
        .contextMenu {
            Button("Remove") { remove(prompt.wrappedValue.id) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button(action: addPrompt) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .disabled(!prompts.canAdd)
            .help(prompts.canAdd ? "Add a prompt" : "The bar shows up to \(QuickPrompts.limit) prompts")

            Divider()
                .frame(height: 14)

            Button(action: removeSelected) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .disabled(removable == nil)
            .help("Remove the selected prompt")

            Spacer()

            Button("Restore Defaults") { prompts = .defaults }
                .disabled(prompts == .defaults)
                .padding(.trailing, 6)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func addPrompt() {
        guard prompts.canAdd else { return }
        let prompt = QuickPrompt(text: "", modes: [.ask, .edit])
        prompts.items.append(prompt)
        selection = prompt.id
        focusedPrompt = prompt.id
    }

    private func removeSelected() {
        guard let id = removable else { return }
        remove(id)
    }

    private func remove(_ id: QuickPrompt.ID) {
        prompts.items.removeAll { $0.id == id }
        if selection == id { selection = nil }
        if focusedPrompt == id { focusedPrompt = nil }
    }
}

/// Which of the bar's modes a prompt shows in, as a quiet popup: both, or just one.
/// Never neither, or the prompt would show nowhere.
private struct ModesMenu: View {
    @Binding var modes: Set<QuickPrompt.Mode>

    private static let choices: [Set<QuickPrompt.Mode>] = [[.ask, .edit], [.ask], [.edit]]

    private static func title(for modes: Set<QuickPrompt.Mode>) -> String {
        modes.count > 1 ? "Ask & Edit" : modes.first?.title ?? ""
    }

    var body: some View {
        Menu {
            Picker("Show In", selection: $modes) {
                ForEach(Self.choices, id: \.self) { choice in
                    Text(Self.title(for: choice)).tag(choice)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(Self.title(for: modes))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("Which of the bar's modes this prompt shows in")
    }
}

#Preview {
    @Previewable @State var prompts = QuickPrompts.defaults
    QuickPromptsEditor(prompts: $prompts)
        .padding()
        .frame(width: 460)
}
