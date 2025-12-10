import Foundation

struct AppSettings {
    var provider: ModelProvider
    var baseURL: String
    var model: String
    var instruction: String
    var apiKey: String
}

enum ModelProvider: String, CaseIterable, Identifiable {
    case openAI
    case custom
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI (default)"
        case .custom: return "Custom endpoint"
        case .local: return "Local (Ollama/LM Studio)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .custom: return "https://api.example.com/v1"
        case .local: return "http://localhost:11434/v1"
        }
    }
}

struct SettingsStore {
    private enum Keys {
        static let provider = "settings.provider"
        static let baseURL = "settings.baseURL"
        static let model = "settings.model"
        static let instruction = "settings.instruction"
        static let apiKey = "settings.apiKey"
    }

    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        let providerRaw = defaults.string(forKey: Keys.provider) ?? ModelProvider.openAI.rawValue
        let provider = ModelProvider(rawValue: providerRaw) ?? .openAI
        let baseURL = defaults.string(forKey: Keys.baseURL) ?? provider.defaultBaseURL
        let model = defaults.string(forKey: Keys.model) ?? "gpt-5-nano"
        let instruction = defaults.string(forKey: Keys.instruction) ??
        "Rewrite the text with clearer grammar and tone while preserving the author's intent. Return only the revised text."
        let apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        return AppSettings(
            provider: provider,
            baseURL: baseURL,
            model: model,
            instruction: instruction,
            apiKey: apiKey
        )
    }

    func save(provider: ModelProvider) {
        defaults.set(provider.rawValue, forKey: Keys.provider)
    }

    func save(baseURL: String) {
        defaults.set(baseURL, forKey: Keys.baseURL)
    }

    func save(model: String) {
        defaults.set(model, forKey: Keys.model)
    }

    func save(instruction: String) {
        defaults.set(instruction, forKey: Keys.instruction)
    }

    func save(apiKey: String) {
        defaults.set(apiKey, forKey: Keys.apiKey)
    }
}
