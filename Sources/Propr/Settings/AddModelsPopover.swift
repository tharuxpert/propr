import SwiftUI

/// Adds models from the provider's own catalog, found by search and ticked.
/// Models it does not list are added with `AddCustomModelPopover`.
///
/// A popover rather than part of the editor. A catalog runs to hundreds of rows, and
/// inline it put a scroll view inside the editor's scrolling form.
struct AddModelsPopover: View {
    let catalog: ModelCatalogLoader
    /// Whether the catalog can be requested: the URL is usable and any key it needs
    /// is there to send.
    let canLoad: Bool
    let load: () -> Void
    /// Whether an identifier can still be added. Ones already on the provider are
    /// shown, but not selectable.
    let canAdd: (String) -> Bool
    let onAdd: ([String]) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection: Set<String> = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The rows to show. A provider can list hundreds of models, so the search is the
    /// only practical way to find one.
    private var matches: [String] {
        guard !trimmedQuery.isEmpty else { return catalog.ids }
        return catalog.ids.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// The matches that can still be picked. Select All works on these rather than on
    /// everything, so adding models in bulk means searching for them first.
    private var selectable: [String] {
        matches.filter(canAdd)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                "Search", text: $query,
                prompt: Text(verbatim: "Search models")
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(submit)
            .padding(12)

            Divider()

            list
                .frame(height: 280)

            if !catalog.ids.isEmpty {
                Divider()

                footer
                    .padding(12)
            }
        }
        .frame(width: 400)
        // Opening the popover is the explicit request for the catalog. It is never
        // fetched on its own, because the request sends the API key, so it must only
        // go to a host the user has finished typing.
        .onAppear {
            if canLoad && catalog.ids.isEmpty && !catalog.isFetching { load() }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var list: some View {
        if catalog.isFetching && catalog.ids.isEmpty {
            ProgressView("Loading models…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if catalog.ids.isEmpty {
            status
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if matches.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { id in
                        row(for: id)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// Why there is no catalog to show, and what to do instead.
    private var status: some View {
        VStack(spacing: 8) {
            if let error = catalog.error {
                Text(error.errorDescription ?? "The model list could not be loaded.")
                if canLoad {
                    Button("Try Again", action: load)
                }
            } else {
                Text("Fill in the base URL and API key to browse this provider's models.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
    }

    private func row(for id: String) -> some View {
        let added = !canAdd(id)

        return Toggle(isOn: binding(for: id)) {
            HStack(spacing: 6) {
                Text(id)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if added {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .disabled(added)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        // Long identifiers truncate in the middle, so the full id is always readable.
        .help(id)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            // Only once the list is searched: one press on an unfiltered OpenRouter
            // catalog would add 465 models to Propr's model menus, which then take 465
            // presses to undo. Searching first is what makes a bulk add deliberate.
            if !trimmedQuery.isEmpty && !selectable.isEmpty {
                Button("Select All") { selection.formUnion(selectable) }
            }

            Button("Add") {
                // Taken in catalog order, which is the order the rows are shown in.
                // `selection` is a Set, and sorting it here would use Swift's
                // case-sensitive comparison, a different order from the list.
                add(catalog.ids.filter { selection.contains($0) })
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty)
        }
    }

    private var summary: String {
        if !selection.isEmpty {
            return "\(selection.count) selected"
        }
        if catalog.ids.isEmpty {
            return ""
        }

        let count = matches.count
        let noun = count == 1 ? "model" : "models"
        return trimmedQuery.isEmpty ? "\(count) \(noun)" : "\(count) matching"
    }

    // MARK: - Actions

    /// Return adds what is ticked.
    private func submit() {
        guard !selection.isEmpty else { return }
        add(catalog.ids.filter { selection.contains($0) })
    }

    private func add(_ ids: [String]) {
        onAdd(ids)
        onClose()
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
