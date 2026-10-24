import SwiftUI

/// Adds models to a provider: one search over the provider's own catalog, which also
/// takes a model ID typed by hand, for endpoints that publish no catalog and for
/// models missing from one.
///
/// A popover rather than part of the editor. A catalog runs to hundreds of rows, and
/// inline it put a scroll view inside the editor's scrolling form, with the hand-typed
/// row as a third way in below it.
struct AddModelsPopover: View {
    let catalog: ModelCatalogLoader
    /// Whether the catalog can be requested: the URL is usable and any key it needs
    /// is there to send.
    let canLoad: Bool
    let load: () -> Void
    /// Whether an identifier can still be added. Ones already on the provider are
    /// shown, but not selectable.
    let canAdd: (String) -> Bool
    /// Why an alias cannot be used for a model being added, or nil when it can.
    let aliasError: (String) -> String?
    /// Adds models ticked in the catalog.
    let onAdd: ([String]) -> Void
    /// Adds a typed model ID, with its alias, which may be blank.
    let onAddTyped: (_ id: String, _ alias: String) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var alias = ""
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

    /// The search text as a model ID of its own, offered when the catalog does not
    /// list it exactly.
    private var typedID: String? {
        let id = trimmedQuery
        guard !id.isEmpty, !catalog.ids.contains(id), canAdd(id) else { return nil }
        return id
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                "Search", text: $query,
                prompt: Text(verbatim: catalog.ids.isEmpty ? "Model ID" : "Search or type a model ID")
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(submit)
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if let typedID {
                    typedRow(typedID)
                    Divider()
                }
                list
            }
            .frame(height: 280)

            // Without a catalog there is nothing to tick: a typed ID is added from
            // its own row, or with Return.
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
            if typedID == nil {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                Spacer(minLength: 0)
            }
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
                Text("Fill in the base URL and API key to browse this provider's models, or type a model ID above.")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
    }

    /// The typed ID, with a field to give it the name Propr shows in its menus.
    private func typedRow(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                Text(id)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(id)

                Spacer(minLength: 0)

                TextField("Alias", text: $alias, prompt: Text(verbatim: "Alias (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onSubmit { addTyped(id) }

                Button("Add") { addTyped(id) }
                    .disabled(aliasError(alias) != nil)
            }

            if let message = aliasError(alias) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    /// Return adds what is ticked, or the typed ID, with its alias, when nothing is.
    private func submit() {
        if !selection.isEmpty {
            add(catalog.ids.filter { selection.contains($0) })
        } else if let typedID {
            addTyped(typedID)
        }
    }

    private func addTyped(_ id: String) {
        guard aliasError(alias) == nil else { return }
        onAddTyped(id, alias)
        onClose()
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
