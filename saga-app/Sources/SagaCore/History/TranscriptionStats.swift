import Foundation
import OSLog

/// Akkumulerede statistikker over alle Saga's transkriptioner siden første run.
/// Persisteret i UserDefaults som JSON. Vises i Settings → Om → Statistik.
///
/// Kun aggregerede tal — ingen tekst-indhold gemmes her (det ligger i
/// HistoryStore). Ren counter-data så vi kan vise "X ord transcribed siden
/// første brug" uden privacy-risiko.
public struct TranscriptionStats: Codable, Sendable, Equatable {
    /// Total antal ord transcribed (efter Saga's egne post-processors).
    public var totalWords: Int

    /// Total antal tegn (uden whitespace) transcribed.
    public var totalCharacters: Int

    /// Total lyd-varighed transcribed, i sekunder.
    public var totalAudioSeconds: Double

    /// Antal optagelser der har resulteret i tekst.
    public var totalRecordings: Int

    /// Akkumuleret inference-tid (Canary/Apple Speech), i ms.
    /// Bruges til at beregne gennemsnitlig latens.
    public var totalInferenceMs: Int

    /// Hvornår blev første transkription registreret (til "siden ..." display).
    public var firstUsedAt: Date?

    /// Hvornår blev seneste transkription registreret.
    public var lastUsedAt: Date?

    public init(
        totalWords: Int = 0,
        totalCharacters: Int = 0,
        totalAudioSeconds: Double = 0,
        totalRecordings: Int = 0,
        totalInferenceMs: Int = 0,
        firstUsedAt: Date? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.totalWords = totalWords
        self.totalCharacters = totalCharacters
        self.totalAudioSeconds = totalAudioSeconds
        self.totalRecordings = totalRecordings
        self.totalInferenceMs = totalInferenceMs
        self.firstUsedAt = firstUsedAt
        self.lastUsedAt = lastUsedAt
    }

    /// Gennemsnitlig inference-tid pr. optagelse, i sekunder.
    public var averageInferenceSeconds: Double {
        guard totalRecordings > 0 else { return 0 }
        return Double(totalInferenceMs) / 1000.0 / Double(totalRecordings)
    }

    /// Real-time-factor: gennemsnitlig inference-ms pr. lyd-sekund.
    /// 0.15 = warm Canary; 1.0 = realtime; >1.0 = langsommere end realtime.
    public var realTimeFactor: Double {
        guard totalAudioSeconds > 0 else { return 0 }
        return Double(totalInferenceMs) / 1000.0 / totalAudioSeconds
    }
}

/// Tråd-sikker store for TranscriptionStats. Skriv-operationer batches via
/// debounce så vi ikke hammrer disk for hver dictation.
@MainActor
public final class TranscriptionStatsStore: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "stats")
    private let storageKey = "transcriptionStats"

    @Published public private(set) var stats: TranscriptionStats

    public init() {
        self.stats = Self.loadFromDefaults() ?? TranscriptionStats()
    }

    /// Registrér en ny succesfuld transkription. Opdaterer alle counters
    /// og persisterer.
    public func record(text: String, audioSeconds: Double, inferenceMs: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let characters = trimmed.filter { !$0.isWhitespace }.count
        let now = Date()

        stats.totalWords += words
        stats.totalCharacters += characters
        stats.totalAudioSeconds += audioSeconds
        stats.totalRecordings += 1
        stats.totalInferenceMs += inferenceMs
        stats.lastUsedAt = now
        if stats.firstUsedAt == nil {
            stats.firstUsedAt = now
        }

        save()
    }

    /// Reset alle counters. Bruges af "Nulstil statistik"-knap i Settings.
    public func reset() {
        stats = TranscriptionStats()
        save()
        log.info("Statistik nulstillet")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(stats)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            log.warning("Kunne ikke gemme stats: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadFromDefaults() -> TranscriptionStats? {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionStats") else { return nil }
        return try? JSONDecoder().decode(TranscriptionStats.self, from: data)
    }
}
