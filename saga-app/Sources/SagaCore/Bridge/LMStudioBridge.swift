import Foundation
import OSLog

/// OpenAI-kompatibel HTTP-klient til lokal LM Studio.
/// Default endpoint: http://localhost:1234/v1
public final class LMStudioBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "lmstudio")
    private let urlSession: URLSession
    private let queue = DispatchQueue(label: "dk.parthee.saga.lmstudio.bridge")
    private var _baseURL: URL
    private var _model: String

    public init(baseURL: URL = URL(string: "http://localhost:1234/v1")!,
                model: String = "gemma-4-26b-a4b") {
        self._baseURL = baseURL
        self._model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.urlSession = URLSession(configuration: config)
    }

    public func configure(baseURL: URL, model: String) {
        queue.sync {
            self._baseURL = baseURL
            self._model = model
        }
    }

    public func chat(
        system: String,
        user: String,
        temperature: Double = 0.3,
        maxTokens: Int = 2048
    ) async throws -> String {
        let (baseURL, model) = queue.sync { (_baseURL, _model) }
        let url = baseURL.appendingPathComponent("chat/completions")

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LMStudioError.serverError(status: status, body: body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw LMStudioError.emptyResponse
        }
        return text
    }
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }

    struct Message: Codable {
        let role: String
        let content: String
    }
}

private struct ChatResponse: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let message: Message
        struct Message: Codable {
            let content: String
        }
    }
}

public enum LMStudioError: Error, LocalizedError {
    case serverError(status: Int, body: String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .serverError(let status, let body):
            return "LM Studio fejlede (\(status)): \(body)"
        case .emptyResponse:
            return "LM Studio returnerede en tom respons"
        }
    }
}
