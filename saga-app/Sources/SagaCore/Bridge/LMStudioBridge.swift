import Foundation
import OSLog

/// OpenAI-kompatibel HTTP-klient til lokal LM Studio.
/// Default endpoint: http://localhost:1234/v1
public final class LMStudioBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "lmstudio")
    private let urlSession: URLSession
    private let discoverySession: URLSession
    private let queue = DispatchQueue(label: "dk.parthee.saga.lmstudio.bridge")
    private var _baseURL: URL
    private var _model: String

    /// Almindelige porte hvor en lokal OpenAI-kompatibel server kører:
    /// LM Studio default = 1234. Sekundære valg dækker Ollama og lignende.
    public static let commonPorts: [Int] = [1234, 1235, 8080, 5000, 11434, 8000]

    public init(baseURL: URL = URL(string: "http://localhost:1234/v1")!,
                model: String = "gemma-4-26b-a4b") {
        self._baseURL = baseURL
        self._model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.urlSession = URLSession(configuration: config)

        // Discovery skal være hurtig — 1.5s timeout pr. port
        let discoveryConfig = URLSessionConfiguration.default
        discoveryConfig.timeoutIntervalForRequest = 1.5
        discoveryConfig.timeoutIntervalForResource = 2.0
        self.discoverySession = URLSession(configuration: discoveryConfig)
    }

    public func configure(baseURL: URL, model: String) {
        queue.sync {
            self._baseURL = baseURL
            self._model = model
        }
    }

    /// Scan localhost-porte for OpenAI-kompatible /v1/models endpoints.
    /// Returnerer kun endpoints der svarer 200 OK med en valid model-liste.
    public func discover(ports: [Int] = LMStudioBridge.commonPorts) async -> [DiscoveredEndpoint] {
        await withTaskGroup(of: DiscoveredEndpoint?.self) { group in
            for port in ports {
                group.addTask { [discoverySession] in
                    await Self.probe(port: port, session: discoverySession)
                }
            }
            var results: [DiscoveredEndpoint] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results.sorted { $0.port < $1.port }
        }
    }

    private static func probe(port: Int, session: URLSession) async -> DiscoveredEndpoint? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let payload = try JSONDecoder().decode(LMStudioModels.self, from: data)
            let modelIds = payload.data.map { $0.id }
            guard !modelIds.isEmpty else { return nil }
            return DiscoveredEndpoint(
                port: port,
                baseURL: URL(string: "http://localhost:\(port)/v1")!,
                models: modelIds
            )
        } catch {
            return nil
        }
    }

    public func chat(
        system: String,
        user: String,
        temperature: Double = 0.3,
        maxTokens: Int = 2048
    ) async throws -> String {
        try await chat(system: system, user: user, temperature: temperature, maxTokens: maxTokens, internal: ())
    }

    /// Multi-modal chat med ét billede (PNG-bytes). Bruges af VisionMode.
    /// Antager LM Studio-modellen er vision-capable (llava, gemma-4-vision, etc.).
    public func chatWithImage(
        system: String,
        userText: String,
        imagePNG: Data,
        temperature: Double = 0.3,
        maxTokens: Int = 512
    ) async throws -> String {
        let (baseURL, model) = queue.sync { (_baseURL, _model) }
        let url = baseURL.appendingPathComponent("chat/completions")

        let base64 = imagePNG.base64EncodedString()
        let dataURL = "data:image/png;base64,\(base64)"

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": dataURL]],
                ]],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 120  // vision er langsommere

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

    private func chat(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        internal: Void
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

    /// Streaming chat med multi-turn message-history. Bruges af Companion-mode
    /// så TTS kan starte ved første sætning i stedet for at vente på fuldt svar.
    ///
    /// Yielder content-deltas fra OpenAI-kompatibel SSE response. Hvis serveren
    /// ikke understøtter streaming (returnerer non-SSE), falder vi tilbage til
    /// non-streaming `chat`-vejen og yielder den komplette respons som ét chunk.
    public func chatStream(
        messages: [CompanionMessage],
        temperature: Double = 0.4,
        maxTokens: Int = 1024
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                do {
                    try await self.runChatStream(
                        messages: messages,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func runChatStream(
        messages: [CompanionMessage],
        temperature: Double,
        maxTokens: Int,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let (baseURL, model) = queue.sync { (_baseURL, _model) }
        let url = baseURL.appendingPathComponent("chat/completions")

        let openAIMessages = messages.map { msg -> [String: Any] in
            // Multi-modal hvis screenshot er vedhæftet (kun user-messages)
            if msg.role == .user, let png = msg.screenshotPNG {
                let base64 = png.base64EncodedString()
                let dataURL = "data:image/png;base64,\(base64)"
                return [
                    "role": msg.role.rawValue,
                    "content": [
                        ["type": "text", "text": msg.content],
                        ["type": "image_url", "image_url": ["url": dataURL]],
                    ],
                ]
            }
            return ["role": msg.role.rawValue, "content": msg.content]
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": openAIMessages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": true,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 120

        let (bytes, resp) = try await urlSession.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw LMStudioError.serverError(status: status, body: "stream-init fejlede")
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        // Hvis serveren ignorerer stream=true og returnerer JSON (ikke SSE),
        // saml hele body og parse som non-streaming response.
        if !contentType.contains("event-stream") {
            log.warning("Server returnerede ikke SSE — falder til non-streaming")
            var data = Data()
            for try await byte in bytes {
                if Task.isCancelled { return }
                data.append(byte)
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            if let text = decoded.choices.first?.message.content, !text.isEmpty {
                continuation.yield(text)
            }
            return
        }

        // SSE-flow — line-by-line parsing
        for try await line in bytes.lines {
            if Task.isCancelled { return }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payloadStr = String(trimmed.dropFirst("data:".count))
                .trimmingCharacters(in: .whitespaces)

            if payloadStr == "[DONE]" {
                return
            }
            guard !payloadStr.isEmpty,
                  let data = payloadStr.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                if let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                    continuation.yield(delta)
                }
            } catch {
                // Tolerér enkelte mal-formede chunks — log men afbryd ikke
                log.debug("SSE-chunk-decode fejlede: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

struct LMStudioModels: Codable {
    let data: [Model]
    struct Model: Codable {
        let id: String
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

private struct StreamChunk: Codable {
    let choices: [Choice]
    struct Choice: Codable {
        let delta: Delta?
        struct Delta: Codable {
            let content: String?
        }
    }
}

public struct DiscoveredEndpoint: Sendable, Identifiable, Equatable {
    public let port: Int
    public let baseURL: URL
    public let models: [String]

    public var id: Int { port }

    public var displayName: String {
        let modelLabel = models.first.map { $0.split(separator: "/").last.map(String.init) ?? $0 } ?? "ingen"
        return "localhost:\(port) · \(modelLabel)\(models.count > 1 ? " (+\(models.count - 1))" : "")"
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
