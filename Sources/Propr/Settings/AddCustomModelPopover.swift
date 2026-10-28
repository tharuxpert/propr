import SwiftUI

/// Adds a model by its ID, typed by hand, with an optional alias. For endpoints that
/// publish no model list, and for models missing from one.
struct AddCustomModelPopover: View {
    /// Whether an identifier can still be added.
    let canAdd: (String) -> Bool
    /// Why an alias cannot be used for a model being added, or nil when it can.
    let aliasError: (String) -> String?
    let onAdd: (_ id: String, _ alias: String) -> Void
    let onClose: () -> Void

    @State private var id = ""
    @State private var alias = ""

    private var trimmedID: String {
        id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first rule the typed values break, once there is an ID to judge.
    private var error: String? {
        guard !trimmedID.isEmpty else { return nil }
        if !canAdd(trimmedID) { return "This model is already added." }
        return aliasError(alias)
    }

    private var canSubmit: Bool {
        !trimmedID.isEmpty && error == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Custom Model")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Model ID")
                        .gridColumnAlignment(.trailing)
                    TextField("Model ID", text: $id, prompt: Text(verbatim: "e.g. glm-5.3"))
                        .labelsHidden()
                }
                GridRow {
                    Text("Alias")
                    TextField("Alias", text: $alias, prompt: Text(verbatim: "Optional"))
                        .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(add)

            Group {
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                } else {
                    Text("The ID must match the provider's exactly. The alias is what Propr shows in its menus.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func add() {
        guard canSubmit else { return }
        onAdd(trimmedID, alias)
        onClose()
    }
}
