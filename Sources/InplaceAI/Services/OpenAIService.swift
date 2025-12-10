import Foundation

struct OpenAIService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func rewrite(text: String, instruction: String, apiKey: String, model: String, baseURL: String) async throws -> Suggestion {
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

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let rewritten = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              rewritten.isEmpty == false
        else {
            throw NSError(domain: "network", code: -2, userInfo: [NSLocalizedDescriptionKey: "Model returned no content"])
        }

        return Suggestion(
            originalText: text,
            rewrittenText: rewritten,
            explanation: nil
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
        guard url.scheme != nil else {
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
                .init(role: "system", content: "You are a writing assistant that rewrites user-selected text inline."),
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
