import SwiftUI

/// One model in the provider editor: the name Propr shows for it, its identifier
/// beneath when an alias hides it, and a menu to rename or remove it.
struct EndpointModelRow: View {
    let model: CustomModel
    /// Why an alias cannot be used for this model, or nil when it can.
    let aliasError: (String) -> String?
    let onRename: (String) -> Void
    let onRemove: () -> Void

    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.alias != nil {
                    Text(model.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .help(model.name)

            Spacer(minLength: 8)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Options for \(model.displayName)")
            .popover(isPresented: $isRenaming, arrowEdge: .trailing) {
                AliasEditor(
                    model: model,
                    error: aliasError,
                    onSave: onRename,
                    onClose: { isRenaming = false }
                )
            }
        }
        .contentShape(Rectangle())
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button(model.alias == nil ? "Add Alias…" : "Rename…") { isRenaming = true }
        Divider()
        Button("Remove", role: .destructive, action: onRemove)
    }
}

/// Edits the name Propr shows for a model in its menus.
private struct AliasEditor: View {
    let model: CustomModel
    let error: (String) -> String?
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var alias: String

    init(
        model: CustomModel, error: @escaping (String) -> String?,
        onSave: @escaping (String) -> Void, onClose: @escaping () -> Void
    ) {
        self.model = model
        self.error = error
        self.onSave = onSave
        self.onClose = onClose
        _alias = State(initialValue: model.alias ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alias")
                    .font(.headline)
                Text("The name Propr shows in its menus. Leave it blank to show the model ID.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The identifier is the placeholder: it is what shows when this is blank.
            TextField("Alias", text: $alias, prompt: Text(verbatim: model.name))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            if let message = error(alias) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(error(alias) != nil)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func save() {
        guard error(alias) == nil else { return }
        onSave(alias)
        onClose()
    }
}
