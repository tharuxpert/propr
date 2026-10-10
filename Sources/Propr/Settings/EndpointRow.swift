import SwiftUI

/// One configured provider in the Models pane: its logo, its name and host,
/// and how many models it offers, with Edit and Remove at the trailing edge.
struct EndpointRow: View {
    let endpoint: CustomEndpoint
    let onEdit: () -> Void
    let onRemove: () -> Void

    /// The host reads better than the full URL, which mostly repeats `/v1`.
    private var host: String {
        URL(string: endpoint.baseURL)?.host() ?? endpoint.baseURL
    }

    private var modelCount: String {
        switch endpoint.models.count {
        case 0: "No models"
        case 1: "1 model"
        default: "\(endpoint.models.count) models"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ProviderLogo(name: endpoint.name, baseURL: endpoint.baseURL)

            VStack(alignment: .leading, spacing: 1) {
                Text(endpoint.name)
                Text("\(host) · \(modelCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Edit…", action: onEdit)

            Menu {
                Button("Remove Provider…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Remove Provider…", role: .destructive, action: onRemove)
        }
    }
}

#Preview {
    Form {
        EndpointRow(
            endpoint: CustomEndpoint(
                name: "My Groq",
                baseURL: "https://api.groq.com/openai/v1",
                models: [
                    CustomModel(name: "llama-3.3-70b-versatile", alias: "Llama 3.3 70B"),
                    CustomModel(name: "openai/gpt-oss-120b"),
                ]
            ),
            onEdit: {},
            onRemove: {}
        )
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 140)
}
