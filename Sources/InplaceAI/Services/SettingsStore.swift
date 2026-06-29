import Foundation

struct AppSettings {
    var provider: ModelProvider
    var baseURL: String
    var model: String
    var instruction: String
    var primaryTranslationLanguage: TranslationLanguage
    var secondaryTranslationLanguage: TranslationLanguage
    var apiKey: String
    var startAtLogin: Bool
}

enum TranslationLanguage: String, CaseIterable, Identifiable {
    case english
    case chinese
    case spanish
    case french
    case german
    case japanese
    case korean
    case portuguese
    case italian
    case russian
    case arabic
    case hindi

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
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
        static let primaryTranslationLanguage = "settings.translation.primaryLanguage"
        static let secondaryTranslationLanguage = "settings.translation.secondaryLanguage"
        static let apiKey = "settings.apiKey"
        static let startAtLogin = "settings.startAtLogin"
    }

    private static let keychainService = "com.inplaceai.desktop"
    private static let keychainAPIKeyAccount = "openai.apiKey"

    private let settingsFile: URL
    private let keychain: KeychainStore

    init() {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundle = "com.inplaceai.desktop"
        let dir = directory.appendingPathComponent(bundle, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.settingsFile = dir.appendingPathComponent("settings.json")
        self.keychain = KeychainStore(
            service: Self.keychainService,
            account: Self.keychainAPIKeyAccount
        )
    }

    private func loadDict() -> [String: String]? {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return nil }
        let data = try? Data(contentsOf: settingsFile)
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    func load() -> AppSettings {
        let dict = loadDict()
        let providerRaw = dict?[Keys.provider] ?? ModelProvider.openAI.rawValue
        let provider = ModelProvider(rawValue: providerRaw) ?? .openAI
        let baseURL = dict?[Keys.baseURL] ?? provider.defaultBaseURL
        let model = dict?[Keys.model] ?? "gpt-5-nano"
        let instruction = dict?[Keys.instruction] ??
        "Rewrite the text with clearer grammar and tone while preserving the author's intent. Return only the revised text."
        let primaryTranslationLanguage = TranslationLanguage(
            rawValue: dict?[Keys.primaryTranslationLanguage] ?? ""
        ) ?? .english
        let secondaryTranslationLanguage = TranslationLanguage(
            rawValue: dict?[Keys.secondaryTranslationLanguage] ?? ""
        ) ?? .chinese
        let apiKey = loadAPIKey(migratingFrom: dict)
        let startAtLogin = dict?[Keys.startAtLogin] == "true"
        return AppSettings(
            provider: provider,
            baseURL: baseURL,
            model: model,
            instruction: instruction,
            primaryTranslationLanguage: primaryTranslationLanguage,
            secondaryTranslationLanguage: secondaryTranslationLanguage,
            apiKey: apiKey,
            startAtLogin: startAtLogin
        )
    }

    /// Reads the API key from the Keychain. If a legacy plaintext value exists in
    /// settings.json, migrates it into the Keychain and scrubs it from disk.
    private func loadAPIKey(migratingFrom dict: [String: String]?) -> String {
        if let keychainKey = keychain.read(), !keychainKey.isEmpty {
            if dict?[Keys.apiKey] != nil {
                scrubLegacyAPIKey()
            }
            return keychainKey
        }

        if let legacy = dict?[Keys.apiKey], !legacy.isEmpty {
            keychain.write(legacy)
            scrubLegacyAPIKey()
            return legacy
        }

        return ""
    }

    private func scrubLegacyAPIKey() {
        guard var dict = loadDict() else { return }
        if dict.removeValue(forKey: Keys.apiKey) != nil {
            save(dict)
        }
    }

    func save(provider: ModelProvider) {
        var dict = loadDict() ?? [:]
        dict[Keys.provider] = provider.rawValue
        save(dict)
    }

    func save(baseURL: String) {
        var dict = loadDict() ?? [:]
        dict[Keys.baseURL] = baseURL
        save(dict)
    }

    func save(model: String) {
        var dict = loadDict() ?? [:]
        dict[Keys.model] = model
        save(dict)
    }

    func save(instruction: String) {
        var dict = loadDict() ?? [:]
        dict[Keys.instruction] = instruction
        save(dict)
    }

    func save(primaryTranslationLanguage: TranslationLanguage) {
        var dict = loadDict() ?? [:]
        dict[Keys.primaryTranslationLanguage] = primaryTranslationLanguage.rawValue
        save(dict)
    }

    func save(secondaryTranslationLanguage: TranslationLanguage) {
        var dict = loadDict() ?? [:]
        dict[Keys.secondaryTranslationLanguage] = secondaryTranslationLanguage.rawValue
        save(dict)
    }

    func save(apiKey: String) {
        if apiKey.isEmpty {
            keychain.delete()
        } else {
            keychain.write(apiKey)
        }
        scrubLegacyAPIKey()
    }

    func save(startAtLogin: Bool) {
        var dict = loadDict() ?? [:]
        dict[Keys.startAtLogin] = startAtLogin ? "true" : "false"
        save(dict)
    }

    private func save(_ dict: [String: String]) {
        let data = try? JSONSerialization.data(withJSONObject: dict)
        try? data?.write(to: settingsFile)
    }
}
