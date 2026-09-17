import Foundation

/// A provider Propr can offer as a one-click starting point in Settings.
///
/// Deliberately carries no model list. Model identifiers churn constantly — Groq
/// retired its Llama 3.x ids, DeepSeek discontinued `deepseek-chat` — and a list
/// baked into the app is stale the moment it ships. Quick Start prefills the base
/// URL and takes the key; the user names the models they actually have access to,
/// the same way the custom endpoint flow works.
struct BuiltInProvider: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let requiresKey: Bool
    let description: String
    let apiKeyExample: String?           // Example prefix for placeholder (e.g. "sk-...")
}

extension BuiltInProvider {
    static let all: [BuiltInProvider] = [
        BuiltInProvider(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            requiresKey: true,
            description: "Official OpenAI models",
            apiKeyExample: "sk-proj-..."   // Modern project keys; legacy sk- keys also work
        ),
        BuiltInProvider(
            name: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            requiresKey: true,
            description: "Very fast inference",
            apiKeyExample: "gsk_..."
        ),
        BuiltInProvider(
            name: "xAI (Grok)",
            baseURL: "https://api.x.ai/v1",
            requiresKey: true,
            description: "Grok models from xAI",
            apiKeyExample: "xai-..."
        ),
        BuiltInProvider(
            name: "Together AI",
            baseURL: "https://api.together.xyz/v1",
            requiresKey: true,
            description: "Large selection of open models",
            apiKeyExample: "your-together-key"   // No standard short prefix published
        ),
        BuiltInProvider(
            name: "Fireworks AI",
            baseURL: "https://api.fireworks.ai/inference/v1",
            requiresKey: true,
            description: "Fast open-source inference",
            apiKeyExample: "fw_..."
        ),
        BuiltInProvider(
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            requiresKey: true,
            description: "Access many providers through one key",
            apiKeyExample: "sk-or-v1-..."
        ),
        BuiltInProvider(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",   // Official OpenAI-compatible base ( /v1 also works in most clients)
            requiresKey: true,
            description: "Strong coding & reasoning models",
            apiKeyExample: "sk-..."
        ),
        BuiltInProvider(
            name: "Local (Ollama / LM Studio)",
            baseURL: "http://127.0.0.1:11434/v1",
            requiresKey: false,
            description: "Run models locally (no API key needed)",
            apiKeyExample: nil
        )
    ]
}