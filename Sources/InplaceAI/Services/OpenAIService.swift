import Foundation

struct OpenAIService {
    private let session: URLSession
    private let synchronousTimeout: TimeInterval = 60

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(
        text: String,
        instruction: String,
        apiKey: String,
        model: String,
        baseURL: String,
        promptTitle: String? = nil,
        tool: WritingTool? = nil
    ) async throws -> Suggestion {
        let request = try makeRequest(
            text: text,
            instruction: instruction,
            apiKey: apiKey,
            model: model,
            baseURL: baseURL
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard 200..<300 ~= http.statusCode else {
            let message = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "network", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let rewritten = try decodeRewrittenText(from: data)

        return Suggestion(
            originalText: text,
            rewrittenText: rewritten,
            explanation: nil,
            instruction: instruction,
            promptTitle: promptTitle ?? PromptLibrary.title(for: instruction),
            tool: tool
        )
    }

    func rewriteSynchronously(
        text: String,
        instruction: String,
        apiKey: String,
        model: String,
        baseURL: String,
        promptTitle: String? = nil,
        tool: WritingTool? = nil
    ) throws -> Suggestion {
        let request = try makeRequest(
            text: text,
            instruction: instruction,
            apiKey: apiKey,
            model: model,
            baseURL: baseURL
        )

        let semaphore = DispatchSemaphore(value: 0)
        let state = SynchronousRequestState()

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                state.complete(.failure(error))
                return
            }

            guard let data, let response else {
                state.complete(.failure(ServiceError.invalidResponse))
                return
            }

            state.complete(.success((data, response)))
        }
        task.resume()

        guard semaphore.wait(timeout: .now() + synchronousTimeout) == .success else {
            task.cancel()
            throw ServiceError.timedOut
        }

        guard let completedResult = state.result() else {
            throw ServiceError.invalidResponse
        }

        let (data, response) = try completedResult.get()

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.http(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let rewritten = try decodeRewrittenText(from: data)
        return Suggestion(
            originalText: text,
            rewrittenText: rewritten,
            explanation: nil,
            instruction: instruction,
            promptTitle: promptTitle ?? PromptLibrary.title(for: instruction),
            tool: tool
        )
    }

    private func makeRequest(
        text: String,
        instruction: String,
        apiKey: String,
        model: String,
        baseURL: String
    ) throws -> URLRequest {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasSuffix("/") {
            trimmed.append("/")
        }
        guard let root = URL(string: trimmed) else {
            throw NSError(domain: "config", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])
        }
        let url = root.appendingPathComponent("chat/completions")
        guard ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw NSError(domain: "config", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OpenAIRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You are a writing assistant that transforms user-selected text according to the requested instruction."),
                .init(role: "user", content: """
                INSTRUCTION:
                \(instruction)

                TEXT:
                \(text)
                """)
            ],
            temperature: 1.0
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func decodeRewrittenText(from data: Data) throws -> String {
        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let rewritten = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              rewritten.isEmpty == false
        else {
            throw ServiceError.emptyModelResponse
        }

        return rewritten
    }
}

enum ServiceError: LocalizedError {
    case invalidResponse
    case timedOut
    case emptyModelResponse
    case http(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from the model provider."
        case .timedOut:
            return "The model provider did not respond in time."
        case .emptyModelResponse:
            return "The model returned no content."
        case .http(let statusCode, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Model provider returned HTTP \(statusCode)."
            }
            return "Model provider returned HTTP \(statusCode): \(trimmed)"
        }
    }
}

private final class SynchronousRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<(Data, URLResponse), Error>?

    func complete(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }

    func result() -> Result<(Data, URLResponse), Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

private struct OpenAIRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if let temperature {
            try container.encode(temperature, forKey: .temperature)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
    }
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
