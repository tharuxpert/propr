import SwiftUI

/// A configured endpoint in the list: its name, base URL and the models it exposes,
/// with edit and delete actions.
struct EndpointRow: View {
    let endpoint: CustomEndpoint
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(endpoint.name)
                    .font(.headline)

                Spacer()

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Edit this endpoint")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Remove this endpoint")
            }

            Text(endpoint.baseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            ForEach(endpoint.models) { model in
                if let alias = model.alias {
                    HStack(spacing: 4) {
                        Text("• \(alias)")
                            .font(.caption)
                        Text("(\(model.name))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("• \(model.name)")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    EndpointRow(
        endpoint: CustomEndpoint(
            name: "My Groq",
            baseURL: "https://api.groq.com/openai/v1",
            models: [
                CustomModel(name: "llama-3.3-70b-versatile", alias: "Llama 3.3 70B"),
                CustomModel(name: "mixtral-8x7b-32768"),
            ]
        ),
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 420)
    .padding()
}
