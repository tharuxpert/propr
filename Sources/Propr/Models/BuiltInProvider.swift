import Foundation

struct BuiltInProvider: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let defaultModels: [String]          // list of model identifiers
    let requiresKey: Bool
    let description: String
    let apiKeyExample: String?           // Example prefix for placeholder (e.g. "sk-...")
}

extension BuiltInProvider {
    static let all: [BuiltInProvider] = [
        BuiltInProvider(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            defaultModels: ["gpt-4o", "gpt-4o-mini", "o1-preview", "o1-mini"],
            requiresKey: true,
            description: "Official OpenAI models",
            apiKeyExample: "sk-proj-..."   // Modern project keys; legacy sk- keys also work
        ),
        BuiltInProvider(
            name: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            defaultModels: [
                "llama-3.1-70b-versatile",
                "llama-3.1-8b-instant",
                "mixtral-8x7b-32768",
                "llama3-70b-8192"
            ],
            requiresKey: true,
            description: "Very fast inference",
            apiKeyExample: "gsk_..."
        ),
        BuiltInProvider(
            name: "xAI (Grok)",
            baseURL: "https://api.x.ai/v1",
            defaultModels: ["grok-2-1212", "grok-2-vision-1212"],
            requiresKey: true,
            description: "Grok models from xAI",
            apiKeyExample: "xai-..."
        ),
        BuiltInProvider(
            name: "Together AI",
            baseURL: "https://api.together.xyz/v1",
            defaultModels: ["meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo", "Qwen/Qwen2.5-72B-Instruct"],
            requiresKey: true,
            description: "Large selection of open models",
            apiKeyExample: "your-together-key"   // No standard short prefix published
        ),
        BuiltInProvider(
            name: "Fireworks AI",
            baseURL: "https://api.fireworks.ai/inference/v1",
            defaultModels: ["accounts/fireworks/models/llama-v3p1-70b-instruct", "accounts/fireworks/models/qwen2p5-72b-instruct"],
            requiresKey: true,
            description: "Fast open-source inference",
            apiKeyExample: "fw_..."
        ),
        BuiltInProvider(
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            defaultModels: ["anthropic/claude-3.5-sonnet", "meta-llama/llama-3.1-70b-instruct", "openai/gpt-4o"],
            requiresKey: true,
            description: "Access many providers through one key",
            apiKeyExample: "sk-or-v1-..."
        ),
        BuiltInProvider(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",   // Official OpenAI-compatible base ( /v1 also works in most clients)
            defaultModels: ["deepseek-chat", "deepseek-reasoner"],
            requiresKey: true,
            description: "Strong coding & reasoning models",
            apiKeyExample: "sk-..."
        ),
        BuiltInProvider(
            name: "Local (Ollama / LM Studio)",
            baseURL: "http://127.0.0.1:11434/v1",
            defaultModels: ["llama3.1", "qwen2.5", "mistral"],
            requiresKey: false,
            description: "Run models locally (no API key needed)",
            apiKeyExample: nil
        )
    ]
}