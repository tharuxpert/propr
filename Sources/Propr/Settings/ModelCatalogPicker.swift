import SwiftUI

/// The model list fetched from a provider, as a searchable multi-select.
///
/// Inline rather than a sheet of its own: the editor is already modal, a second sheet
/// would need its own dismissal semantics inside a fixed-height frame, and the manual
/// model row has to stay visible below as the fallback for endpoints that publish no
/// catalog.
struct ModelCatalogPicker: View {
    /// Every identifier the provider returned, deduplicated and sorted.
    let ids: [String]
    /// Identifiers already on the endpoint: shown, but not selectable.
    let alreadyAdded: Set<String>
    let onAdd: ([String]) -> Void

    @State private var query = ""
    @State private var selection: Set<String> = []

    /// The rows to show. A provider can list hundreds of models, so the filter is the
    /// only practical way to find one by hand.
    private var matches: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ids }
        return ids.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    /// The matches that can still be picked. Select All works on these rather than on
    /// everything, so adding models in bulk means filtering to them first.
    private var selectable: [String] {
        matches.filter { !alreadyAdded.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Filter", text: $query, prompt: Text("Filter \(ids.count) models"))
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(matches, id: \.self) { id in
                        row(for: id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button("Select All") { selection.formUnion(selectable) }
                    // Off until the list is filtered: one press on an unfiltered
                    // OpenRouter catalog would add 465 models to Propr's model menus,
                    // which then take 465 presses to undo. Filtering first is what makes
                    // a bulk add deliberate, and it is also what makes one useful.
                    .disabled(
                        selectable.isEmpty
                            || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                Button("Add Selected") {
                    // Taken in `ids` order, which is the order the rows are shown in.
                    // `selection` is a Set, and sorting it here would use Swift's
                    // case-sensitive comparison — a different order from the list.
                    onAdd(ids.filter { selection.contains($0) })
                    // Added identifiers move into `alreadyAdded` and disable themselves,
                    // so a kept selection would be stale.
                    selection.removeAll()
                    query = ""
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private var summary: String {
        if !selection.isEmpty {
            return selection.count == 1 ? "1 selected" : "\(selection.count) selected"
        }

        let count = matches.count
        let noun = count == 1 ? "model" : "models"
        let filtered = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return filtered ? "\(count) \(noun) matching" : "\(count) \(noun)"
    }

    private func row(for id: String) -> some View {
        let added = alreadyAdded.contains(id)

        return Toggle(isOn: binding(for: id)) {
            HStack(spacing: 6) {
                Text(id)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if added {
                    Text("added")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(added)
        // Long identifiers truncate in the middle, so the full id is always readable.
        .help(id)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }
}

#Preview {
    ModelCatalogPicker(
        ids: [
            "claude-sonnet-4-20250514",
            "gpt-4o",
            "gpt-4o-mini",
            "llama-3.3-70b-versatile",
            "openai/gpt-oss-120b",
            "text-embedding-3-large",
        ],
        alreadyAdded: ["gpt-4o"],
        onAdd: { _ in }
    )
    .padding()
    .frame(width: 440)
}
