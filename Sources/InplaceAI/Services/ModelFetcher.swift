import Foundation

/// Fetches the list of available models from an OpenAI-compatible `/v1/models` endpoint.
/// Results are cached in memory so repeated calls don't re-request.
@MainActor
final class ModelFetcher {
    private var cachedModels: [String]?
    private var lastFetch: Date?
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    /// Returns the list of models. If a cached result exists and is fresh, returns it.
    /// Otherwise makes a network call.
    func fetch(baseURL: String, apiKey: String) async throws -> [String] {
        if let cached = cachedModels, let lastFetch, Date().timeIntervalSince(lastFetch) < cacheTTL {
            return cached
        }
        let models = try await fetchFromAPI(baseURL: baseURL, apiKey: apiKey)
        cachedModels = models
        lastFetch = Date()
        return models
    }

    /// Force a refresh regardless of cache age.
    func refresh(baseURL: String, apiKey: String) async throws -> [String] {
        cachedModels = nil
        return try await fetch(baseURL: baseURL, apiKey: apiKey)
    }

    func clearCache() {
        cachedModels = nil
        lastFetch = nil
    }

    private func fetchFromAPI(baseURL: String, apiKey: String) async throws -> [String] {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasSuffix("/") {
            trimmed.append("/")
        }
        guard let root = URL(string: trimmed) else {
            throw ModelFetchError.invalidURL
        }
        let url = root.appendingPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ModelFetchError.httpError
        }

        let decoded = try JSONDecoder().decode(ModelsAPIResponse.self, from: data)
        let modelIDs = decoded.data.map(\.id)

        // Sort: GPT models first (newest first), then the rest alphabetically
        let gptModels = modelIDs.filter { $0.lowercased().contains("gpt") }
            .sorted { a, b in
                // Prefer newer model series: "gpt-4.1" > "gpt-4o" > "gpt-4"
                let aParts = a.lowercased().split(separator: "-").map(String.init)
                let bParts = b.lowercased().split(separator: "-").map(String.init)
                return aParts.count > bParts.count || a > b
            }
        let otherModels = modelIDs.filter { !$0.lowercased().contains("gpt") }.sorted()

        return gptModels + otherModels
    }

    /// Quick heuristic check: does the endpoint even support `/v1/models`?
    static func supportsModelList(baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("openai.com") || trimmed.contains("api.")
    }
}

enum ModelFetchError: LocalizedError {
    case invalidURL
    case httpError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid base URL for fetching models."
        case .httpError:
            return "Failed to fetch models from the endpoint."
        }
    }
}

private struct ModelsAPIResponse: Decodable {
    struct ModelEntry: Decodable {
        let id: String
    }
    let data: [ModelEntry]
}
