import Foundation

struct AppSettings {
    var model: String
    var instruction: String
    var apiKey: String
}

struct SettingsStore {
    private enum Keys {
        static let model = "settings.model"
        static let instruction = "settings.instruction"
        static let apiKey = "settings.apiKey"
    }

    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        let model = defaults.string(forKey: Keys.model) ?? "gpt-5-nano"
        let instruction = defaults.string(forKey: Keys.instruction) ??
        "Rewrite the text with clearer grammar and tone while preserving the author's intent. Return only the revised text."
        let apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        return AppSettings(model: model, instruction: instruction, apiKey: apiKey)
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
