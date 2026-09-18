import SwiftUI

/// One configured endpoint in the Models list.
///
/// Deliberately has no background of its own — a `List` draws row backgrounds,
/// selection and separators, and a card drawn inside one fights all three.
struct EndpointRow: View {
    let endpoint: CustomEndpoint

    private var modelSummary: String {
        endpoint.models.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name)
                    .font(.body)

                Text(endpoint.baseURL)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !endpoint.models.isEmpty {
                    Text(modelSummary)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        EndpointRow(
            endpoint: CustomEndpoint(
                name: "My Groq",
                baseURL: "https://api.groq.com/openai/v1",
                models: [
                    CustomModel(name: "llama-3.3-70b-versatile", alias: "Llama 3.3 70B"),
                    CustomModel(name: "openai/gpt-oss-120b"),
                ]
            )
        )
    }
    .frame(width: 460, height: 140)
}
