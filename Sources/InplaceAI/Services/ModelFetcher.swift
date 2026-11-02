import Foundation

@MainActor
final class ModelFetcher {
    private struct CacheKey: Equatable {
        let url: URL
        let apiKey: String
    }
    private var cache: (key: CacheKey, models: [String], date: Date)?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(baseURL: String, apiKey: String, forceRefresh: Bool = false) async throws -> [String] {
        let url = try ProviderConfiguration.endpoint(baseURL: baseURL, path: "models")
        let key = CacheKey(url: url, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        if !forceRefresh, let cache, cache.key == key, Date().timeIntervalSince(cache.date) < 300 {
            return cache.models
        }
        var request = URLRequest(url: url)
        if !key.apiKey.isEmpty {
            request.setValue("Bearer \(key.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.http(statusCode: http.statusCode, body: "Could not load models. Check the endpoint and API key, or enter a model name manually.")
        }
        let decoded = try JSONDecoder().decode(ModelsAPIResponse.self, from: data)
        let models = Set(decoded.data.map(\.id).filter { !$0.isEmpty }).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        cache = (key, models, Date())
        return models
    }

    func clearCache() { cache = nil }
}

private struct ModelsAPIResponse: Decodable {
    struct ModelEntry: Decodable { let id: String }
    let data: [ModelEntry]
}
