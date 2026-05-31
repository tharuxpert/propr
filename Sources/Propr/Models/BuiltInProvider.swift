import Foundation

struct BuiltInProvider: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let defaultModels: [String]          // list of model identifiers
    let requiresKey: Bool
    let description: String
}

extension BuiltInProvider {
    static let all: [BuiltInProvider] = [
        BuiltInProvider(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            defaultModels: ["gpt-4o", "gpt-4o-mini", "o1-preview", "o1-mini"],
            requiresKey: true,
            description: "Official OpenAI models"
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
            description: "Very fast inference"
        ),
        BuiltInProvider(
            name: "xAI (Grok)",
            baseURL: "https://api.x.ai/v1",
            defaultModels: ["grok-2-1212", "grok-2-vision-1212"],
            requiresKey: true,
            description: "Grok models from xAI"
        ),
        BuiltInProvider(
            name: "Together AI",
            baseURL: "https://api.together.xyz/v1",
            defaultModels: ["meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo", "Qwen/Qwen2.5-72B-Instruct"],
            requiresKey: true,
            description: "Large selection of open models"
        ),
        BuiltInProvider(
            name: "Fireworks AI",
            baseURL: "https://api.fireworks.ai/inference/v1",
            defaultModels: ["accounts/fireworks/models/llama-v3p1-70b-instruct", "accounts/fireworks/models/qwen2p5-72b-instruct"],
            requiresKey: true,
            description: "Fast open-source inference"
        ),
        BuiltInProvider(
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            defaultModels: ["anthropic/claude-3.5-sonnet", "meta-llama/llama-3.1-70b-instruct", "openai/gpt-4o"],
            requiresKey: true,
            description: "Access many providers through one key"
        ),
        BuiltInProvider(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            defaultModels: ["deepseek-chat", "deepseek-reasoner"],
            requiresKey: true,
            description: "Strong coding & reasoning models"
        ),
        BuiltInProvider(
            name: "Local (Ollama / LM Studio)",
            baseURL: "http://localhost:11434/v1",
            defaultModels: ["llama3.1", "qwen2.5", "mistral"],
            requiresKey: false,
            description: "Run models locally (no API key needed)"
        )
    ]
}