import Foundation
import OSLog

/// Odin-mode: send brugerens forespørgsel til Odin RAG-daemon (port 3838 lokalt
/// eller via Tailscale) og inject top-3 hits som resultat. Svaret er rå
/// citationer fra brugerens eget data — Odin synthesis (LM Studio) kommer i M6.
///
/// Special-cased ligesom Reminder/Vision/Edit fordi den kalder en ekstern HTTP
/// service i stedet for LM Studio direkte.
public enum OdinMode {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "odin-mode")

    /// Triggers brugeren kan sige før forespørgslen.
    /// Eksempel: "odin hvad sagde Lars om budgettet"
    public static let triggers: [String] = [
        "odin:",
        "odin ",
        "spørg odin:",
        "spørg odin ",
        "ask odin:",
        "ask odin ",
    ]

    /// Default endpoint. Kan overrides via UserDefaults `odinMode.endpoint`.
    public static var defaultEndpoint: String {
        if let stored = UserDefaults.standard.string(forKey: "odinMode.endpoint"), !stored.isEmpty {
            return stored
        }
        return "http://localhost:3838"
    }

    public struct Match {
        public let matched: Bool
        public let query: String
    }

    public static func matches(_ text: String) -> Match {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in triggers {
            if lower.hasPrefix(trigger) {
                let stripped = String(text.dropFirst(trigger.count))
                let cleaned = stripped.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:"))
                return Match(matched: true, query: cleaned)
            }
        }
        return Match(matched: false, query: "")
    }

    @MainActor
    public static func run(query: String, controller _: SagaController) async throws -> String {
        guard !query.isEmpty else {
            return "(Odin: ingen forespørgsel)"
        }

        let endpoint = defaultEndpoint
        guard let url = URL(string: "\(endpoint)/v1/search") else {
            throw OdinError.badEndpoint(endpoint)
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "limit": 3])
        request.httpBody = body

        log.info("POST \(url.absoluteString, privacy: .public) — query=\(query.prefix(80), privacy: .public)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OdinError.networkFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OdinError.networkFailed(underlying: NSError(domain: "OdinMode", code: -1))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OdinError.httpStatus(http.statusCode)
        }

        let parsed: SearchResponse
        do {
            parsed = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw OdinError.parseFailed(underlying: error)
        }

        return formatResponse(query: query, response: parsed)
    }

    private static func formatResponse(query: String, response: SearchResponse) -> String {
        if response.hits.isEmpty {
            return "Odin: ingen hits for »\(query)«"
        }

        var lines: [String] = []
        lines.append("Odin · »\(query)« — \(response.count) hits, \(response.latency_ms)ms")
        lines.append("")
        for (idx, hit) in response.hits.prefix(3).enumerated() {
            let date = String((hit.source_date ?? "").prefix(10))
            let typ = hit.source_type
            let snippet = hit
                .text
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(160)
            lines.append("\(idx + 1). [\(typ) \(date)] \(snippet)…")
        }
        return lines.joined(separator: "\n")
    }
}

private struct SearchResponse: Decodable {
    let query: String
    let latency_ms: Int
    let count: Int
    let hits: [SearchHit]
}

private struct SearchHit: Decodable {
    let chunk_id: Int
    let source_id: Int
    let source_type: String
    let source_path: String
    let source_date: String?
    let text: String
    let position: Int
    let distance: Double
    let score: Double
}

public enum OdinError: Error, LocalizedError {
    case badEndpoint(String)
    case networkFailed(underlying: Error)
    case httpStatus(Int)
    case parseFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .badEndpoint(let s):
            return "Odin: ugyldigt endpoint '\(s)'"
        case .networkFailed(let underlying):
            return "Odin daemon ikke reachable (\(underlying.localizedDescription)). Start den med: ODIN_DATA_DIR=~/.odin node ~/Desktop/Claude/projekter/aktive/odin/packages/daemon/dist/index.js"
        case .httpStatus(let code):
            return "Odin daemon svarede HTTP \(code)"
        case .parseFailed(let underlying):
            return "Odin svar kunne ikke parses: \(underlying.localizedDescription)"
        }
    }
}
