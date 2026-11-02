import Foundation

/// Shared validation for generation and model discovery.
enum ProviderConfiguration {
    static func endpoint(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let root = components.url else {
            throw ConfigurationError.invalidURL
        }
        return root.appendingPathComponent(path)
    }

    static func modelName(_ model: String) throws -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "__custom__" else {
            throw ConfigurationError.missingModel
        }
        return trimmed
    }
}

enum ConfigurationError: LocalizedError {
    case invalidURL
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid http:// or https:// base URL without credentials, a query, or a fragment in Preferences."
        case .missingModel:
            return "Enter a model name in Preferences before using Writing Tools."
        }
    }
}
