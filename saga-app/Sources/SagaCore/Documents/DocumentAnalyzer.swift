import AppKit
import Foundation
import OSLog
import PDFKit

/// Analyserer kontrakter, vilkår og lignende dokumenter for skjulte klausuler:
/// binding-perioder, fortrydelsesfrister, automatiske fornyelser, gebyrer.
/// Bruger LM Studio til selve analysen — chunker lange dokumenter.
@MainActor
public final class DocumentAnalyzer: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "documents")

    @Published public private(set) var lastResult: AnalysisResult?
    @Published public private(set) var isAnalyzing: Bool = false

    public init() {}

    public func openFilePicker() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Vælg dokument til analyse"
        panel.allowedContentTypes = [.pdf, .text, .rtf]
        // .docFormat-uti er ikke direkte tilgængelig som UTType — accept .doc/.docx via filename
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }

    public func analyze(url: URL, controller: SagaController) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let text = try extractText(from: url)
            log.info("Extracted \(text.count, privacy: .public) chars from \(url.lastPathComponent, privacy: .public)")

            let chunks = chunk(text: text, maxChars: 6000)
            log.info("Analyserer \(chunks.count, privacy: .public) chunks")

            var allFindings: [Finding] = []
            for (idx, chunk) in chunks.enumerated() {
                let chunkFindings = try await analyzeChunk(chunk, chunkIndex: idx, totalChunks: chunks.count, controller: controller)
                allFindings.append(contentsOf: chunkFindings)
            }

            // Dedupliker — samme citat i flere chunks (overlap mellem siders bunden + næstes top)
            allFindings = deduplicate(allFindings)

            lastResult = AnalysisResult(
                fileURL: url,
                fileName: url.lastPathComponent,
                charCount: text.count,
                chunkCount: chunks.count,
                findings: allFindings,
                analyzedAt: Date()
            )
        } catch {
            log.error("Analysis fejlede: \(error.localizedDescription, privacy: .public)")
            lastResult = AnalysisResult(
                fileURL: url,
                fileName: url.lastPathComponent,
                charCount: 0,
                chunkCount: 0,
                findings: [],
                analyzedAt: Date(),
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Extraction

    private func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return try extractPDF(url: url)
        case "doc", "docx", "rtf":
            return try extractRichText(url: url)
        case "txt", "md", "markdown":
            return try String(contentsOf: url, encoding: .utf8)
        default:
            // Forsøg som plain text først, fallback til rich text
            if let txt = try? String(contentsOf: url, encoding: .utf8), !txt.isEmpty {
                return txt
            }
            return try extractRichText(url: url)
        }
    }

    private func extractPDF(url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw DocumentError.cannotOpen(url.lastPathComponent)
        }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        guard !text.isEmpty else { throw DocumentError.empty(url.lastPathComponent) }
        return text
    }

    private func extractRichText(url: URL) throws -> String {
        // NSAttributedString understøtter rtf/rtfd/doc/docx via document-attributes.
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        let attr = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        let text = attr.string
        guard !text.isEmpty else { throw DocumentError.empty(url.lastPathComponent) }
        return text
    }

    // MARK: - Chunking

    private func chunk(text: String, maxChars: Int) -> [String] {
        if text.count <= maxChars { return [text] }

        // Split på dobbelt-newline (paragraph-boundary) først, derefter flow ind
        // i chunks indtil maxChars er nået.
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""
        for p in paragraphs {
            if (current.count + p.count + 2) > maxChars && !current.isEmpty {
                chunks.append(current)
                current = p
            } else {
                if !current.isEmpty { current += "\n\n" }
                current += p
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - LLM analyse

    private static let systemPrompt: String = """
    Du analyserer kontrakter og vilkår for SKJULTE klausuler som forbrugeren burde
    bemærke. Returnér KUN gyldig JSON i præcis dette format:

    {"findings": [
      {"category": "binding|fortrydelse|fornyelse|gebyr|opsigelse|andet",
       "severity": "lav|medium|høj",
       "title": "kort beskrivelse",
       "quote": "ordret citat fra teksten",
       "explanation": "hvorfor dette er værd at bemærke (1-2 sætninger)"}
    ]}

    Kategorier:
    - binding: minimumsperiode, lukketid før opsigelse er mulig
    - fortrydelse: deadline for fortrydelse, fortabelse af fortrydelsesret
    - fornyelse: automatisk fornyelse, prisstigninger ved fornyelse
    - gebyr: skjulte gebyrer, mistede beløb, oprettelsesgebyr, opsigelsesgebyr
    - opsigelse: opsigelsesvarsel, krav om skriftlig opsigelse, formkrav
    - andet: alt andet bemærkelsesværdigt

    Severity:
    - høj: betydelige økonomiske eller juridiske konsekvenser
    - medium: moderat ulempe eller omkostning
    - lav: information forbrugeren bør kende, men begrænset risiko

    Kun fund der ER til stede i teksten. Ingen spekulation. Hvis ingenting at flagge:
    {"findings": []}

    Returnér KUN JSON. Ingen forklaring rundt. Ingen markdown-fences.
    """

    private func analyzeChunk(_ chunk: String, chunkIndex: Int, totalChunks: Int, controller: SagaController) async throws -> [Finding] {
        let userPrompt: String
        if totalChunks > 1 {
            userPrompt = "Sektion \(chunkIndex + 1) af \(totalChunks):\n\n\(chunk)"
        } else {
            userPrompt = chunk
        }

        let raw = try await controller.lmStudio.chat(
            system: Self.systemPrompt,
            user: userPrompt,
            temperature: 0.1,
            maxTokens: 2048
        )

        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            return []
        }

        do {
            let resp = try JSONDecoder().decode(FindingsResponse.self, from: data)
            return resp.findings
        } catch {
            log.warning("JSON-parse fejlede for chunk \(chunkIndex, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func deduplicate(_ findings: [Finding]) -> [Finding] {
        var seen: Set<String> = []
        var result: [Finding] = []
        for f in findings {
            // Brug en signature af title+quote-prefix
            let signature = (f.title + "|" + f.quote.prefix(80)).lowercased()
            if !seen.contains(signature) {
                seen.insert(signature)
                result.append(f)
            }
        }
        return result
    }
}

public struct AnalysisResult: Identifiable, Sendable {
    public let id = UUID()
    public let fileURL: URL
    public let fileName: String
    public let charCount: Int
    public let chunkCount: Int
    public let findings: [Finding]
    public let analyzedAt: Date
    public var error: String? = nil

    public var hasFindings: Bool { !findings.isEmpty }
    public var highSeverityCount: Int { findings.filter { $0.severity == "høj" }.count }
}

public struct Finding: Codable, Identifiable, Sendable, Hashable {
    public var id: String { (title + quote.prefix(40)).lowercased() }
    public let category: String
    public let severity: String
    public let title: String
    public let quote: String
    public let explanation: String

    public var severityColor: String {
        switch severity.lowercased() {
        case "høj": return "red"
        case "medium": return "orange"
        default: return "secondary"
        }
    }

    public var categoryIcon: String {
        switch category.lowercased() {
        case "binding": return "lock"
        case "fortrydelse": return "arrow.uturn.backward.circle"
        case "fornyelse": return "arrow.triangle.2.circlepath"
        case "gebyr": return "dollarsign.circle"
        case "opsigelse": return "xmark.octagon"
        default: return "exclamationmark.circle"
        }
    }
}

private struct FindingsResponse: Codable {
    let findings: [Finding]
}

public enum DocumentError: Error, LocalizedError {
    case cannotOpen(String)
    case empty(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let name): return "Kunne ikke åbne '\(name)'"
        case .empty(let name): return "'\(name)' indeholder ingen tekst"
        case .unsupportedFormat(let ext): return "Format '\(ext)' er ikke understøttet"
        }
    }
}
