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

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove \(endpoint.name)")
            .accessibilityLabel("Remove \(endpoint.name)")
        }
        // The columns form lines its label up with this row's first baseline, which
        // would be the provider name, high on the logo. Report the baseline as the
        // row's middle instead, so "Providers" sits level with the logo's centre.
        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Remove Provider…", role: .destructive, action: onRemove)
        }
    }
}

#Preview {
    VStack {
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
    .padding()
    .frame(width: 440)
}
