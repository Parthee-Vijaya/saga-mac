import Foundation
import OSLog

/// Persistent ring-buffer af de seneste N transcript-events. Gemmes som JSON
/// i ``~/Library/Application Support/Saga/history.json``.
@MainActor
public final class HistoryStore: ObservableObject {
    public static let maxEntries = 100

    private let log = Logger(subsystem: "dk.parthee.saga", category: "history")
    private let fileURL: URL

    @Published public private(set) var entries: [TranscriptEntry] = []

    public init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saga", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.fileURL = supportDir.appendingPathComponent("history.json")
        load()
    }

    public func append(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder.iso8601().decode([TranscriptEntry].self, from: data)
            entries = decoded
        } catch {
            log.warning("Kunne ikke læse history: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder.iso8601().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.warning("Kunne ikke gemme history: \(error.localizedDescription)")
        }
    }
}

public struct TranscriptEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let rawText: String
    public let processedText: String
    public let modeId: String?
    public let durationMs: Int
    public let inferenceMs: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        processedText: String,
        modeId: String?,
        durationMs: Int,
        inferenceMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.processedText = processedText
        self.modeId = modeId
        self.durationMs = durationMs
        self.inferenceMs = inferenceMs
    }

    public var wasModeApplied: Bool { modeId != nil }

    public var rtf: Double {
        guard durationMs > 0 else { return 0 }
        return Double(inferenceMs) / Double(durationMs)
    }
}

extension JSONEncoder {
    static func iso8601() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}

extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
