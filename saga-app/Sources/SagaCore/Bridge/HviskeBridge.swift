import Foundation
import OSLog

/// HTTP-klient til saga-sidecar /transcribe.
public final class HviskeBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "hviske")
    private let urlSession: URLSession
    private let queue = DispatchQueue(label: "dk.parthee.saga.hviske.bridge")
    private var _port: UInt16?

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }

    public func update(port: UInt16) {
        queue.sync { self._port = port }
    }

    public var currentPort: UInt16? {
        queue.sync { _port }
    }

    private var port: UInt16? {
        queue.sync { _port }
    }

    public func transcribe(pcm: CapturedAudio) async throws -> TranscribeResult {
        guard let port else { throw HviskeError.notReady }
        guard pcm.duration >= 0.1 else { throw HviskeError.audioTooShort }

        let url = URL(string: "http://127.0.0.1:\(port)/transcribe")!
        let boundary = "saga-\(UUID().uuidString)"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendField(name: "encoding", value: "pcm16", boundary: boundary)
        body.appendField(name: "sample_rate", value: "\(pcm.sampleRate)", boundary: boundary)
        body.appendField(name: "language", value: "da", boundary: boundary)
        body.appendFile(
            name: "audio",
            filename: "audio.pcm",
            contentType: "application/octet-stream",
            data: pcm.pcm16Data,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let t0 = Date()
        let (data, resp) = try await urlSession.data(for: req)
        let elapsed = Date().timeIntervalSince(t0)

        guard let http = resp as? HTTPURLResponse else {
            throw HviskeError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw HviskeError.serverError(status: http.statusCode, body: body)
        }

        let result = try JSONDecoder().decode(TranscribeResult.self, from: data)
        log.info("Transcribe ok: \(String(format: "%.2f", elapsed))s round-trip, rtf=\(result.rtf), text=\"\(result.text.prefix(80))\"")
        return result
    }
}

public struct TranscribeResult: Codable, Sendable {
    public let text: String
    public let durationMs: Int
    public let inferenceMs: Int
    public let rtf: Double

    enum CodingKeys: String, CodingKey {
        case text
        case durationMs = "duration_ms"
        case inferenceMs = "inference_ms"
        case rtf
    }
}

public enum HviskeError: Error, LocalizedError {
    case notReady
    case audioTooShort
    case invalidResponse
    case serverError(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .notReady: return "Hviske-sidecar er ikke klar endnu"
        case .audioTooShort: return "Optagelsen er for kort"
        case .invalidResponse: return "Sidecar returnerede en ugyldig respons"
        case .serverError(let status, let body): return "Sidecar fejlede (\(status)): \(body)"
        }
    }
}

extension Data {
    fileprivate mutating func appendField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    fileprivate mutating func appendFile(name: String, filename: String, contentType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
