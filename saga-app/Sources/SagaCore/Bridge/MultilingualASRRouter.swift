import Foundation
import OSLog

/// Protocol for sprog-parametriserede ASR-bridges (Canary, Hviske). Gør
/// MultilingualASRRouter testbar — tests kan injicere mock-bridges uden
/// CoreML-modeller på disk.
public protocol DanishASRBridging: Sendable {
    var isReady: Bool { get }
    func transcribe(pcm: CapturedAudio, language: String) async throws -> TranscribeResult
}

/// Protocol for Apple Speech-fallback (locale-baseret API frem for sprog-kode).
public protocol AppleSpeechBridging: Sendable {
    func transcribe(pcm: CapturedAudio, languageCode: String) async throws -> TranscribeResult
}

/// Router der vælger ASR-backend baseret på sprog-kode. Canary-1b-v2 supporterer
/// 25 europæiske sprog inkl. dansk, engelsk, tysk, spansk osv. — dem foretrækker
/// vi for kvalitet. For sprog Canary IKKE supporterer (tamilsk, hindi, japansk
/// osv.) bruger vi Apple's SFSpeechRecognizer som fallback.
public final class MultilingualASRRouter: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "asr-router")

    /// Sprog Canary-1b-v2 supporterer (25 EU-sprog). Identifiers er Saga's
    /// short-codes (ikke locale-codes).
    public static let canarySupportedLanguages: Set<String> = [
        "da", "en", "de", "es", "fr", "it", "pt", "nl", "pl", "ru",
        "cs", "sk", "hu", "ro", "bg", "hr", "sr", "sl", "el",
        "et", "lv", "lt", "fi", "sv", "no",
    ]

    private let canary: any DanishASRBridging
    private let hviske: any DanishASRBridging
    private let apple: any AppleSpeechBridging

    public init(canary: any DanishASRBridging, hviske: any DanishASRBridging, apple: any AppleSpeechBridging) {
        self.canary = canary
        self.hviske = hviske
        self.apple = apple
    }

    /// Transcribe `pcm` på det valgte sprog. Routing-prioritet:
    /// 1. Dansk + preferredDanishEngine = .hviske + Hviske er klar → Hviske
    /// 2. Sprog supporteret af Canary → Canary
    /// 3. Fallback → Apple Speech
    ///
    /// Resultatet stemples med `engineLabel` for den engine der FAKTISK
    /// kørte — inkl. fallback-pathen (Hviske fejler → label er "Canary").
    public func transcribe(
        pcm: CapturedAudio,
        language: SagaLanguage,
        preferredDanishEngine: DanishEngine = .canary
    ) async throws -> TranscribeResult {
        // Dansk + Hviske valgt + Hviske klar → brug Hviske
        if language == .danish, preferredDanishEngine == .hviske, hviske.isReady {
            log.info("Routing til Hviske for dansk")
            do {
                return try await hviske.transcribe(pcm: pcm, language: "da").withEngineLabel("Hviske")
            } catch let hviskeError {
                log.warning("Hviske fejlede, falder tilbage til Canary: \(hviskeError.localizedDescription, privacy: .public)")
                do {
                    return try await canary.transcribe(pcm: pcm, language: "da").withEngineLabel("Canary")
                } catch let canaryError {
                    // Begge engines nede — giv en samlet, brugbar fejl frem for
                    // den rå Canary-fejl alene.
                    log.error("Begge dansk-engines fejlede. Hviske: \(hviskeError.localizedDescription, privacy: .public) · Canary: \(canaryError.localizedDescription, privacy: .public)")
                    throw ASRRouterError.bothDanishEnginesFailed(
                        hviske: hviskeError.localizedDescription,
                        canary: canaryError.localizedDescription
                    )
                }
            }
        }

        if Self.canarySupportedLanguages.contains(language.canaryCode) {
            log.info("Routing til Canary for \(language.canaryCode, privacy: .public)")
            return try await canary.transcribe(pcm: pcm, language: language.canaryCode).withEngineLabel("Canary")
        } else {
            log.info("Routing til Apple Speech for \(language.appleLocale, privacy: .public)")
            return try await apple.transcribe(pcm: pcm, languageCode: language.appleLocale).withEngineLabel("Apple Speech")
        }
    }
}

/// Router-specifikke fejl der kombinerer information fra flere engines.
public enum ASRRouterError: Error, LocalizedError {
    case bothDanishEnginesFailed(hviske: String, canary: String)

    public var errorDescription: String? {
        switch self {
        case .bothDanishEnginesFailed(let hviske, let canary):
            return "Begge dansk-engines fejlede. Hviske: \(hviske) — Canary: \(canary). Tjek Indstillinger → Stemme for engine-status."
        }
    }
}

/// ASR-engine valg for dansk dictation. Andre sprog bruger altid
/// Canary eller Apple Speech (Hviske er dansk-only).
public enum DanishEngine: String, CaseIterable, Sendable, Codable {
    /// NVIDIA Canary-1b-v2 — multi-lingual baseline. Default.
    case canary

    /// syv.ai Hviske-v5.3 — premium dansk via custom Conformer.
    /// Kræver hviske-coreml-projektet er færdigt (F1-F8).
    case hviske

    public var displayName: String {
        switch self {
        case .canary: return "Canary (multilingual)"
        case .hviske: return "Hviske (dansk-først)"
        }
    }

    public var description: String {
        switch self {
        case .canary:
            return "NVIDIA Canary-1b-v2 — 25 EU-sprog, robust multilingual baseline. Default for alle sprog."
        case .hviske:
            return "syv.ai Hviske-v5.3 — Conformer 2B fine-tuned på dansk samtale-data. Bedre WER på naturlig tale, men kun dansk. Kræver hviske-coreml er installeret."
        }
    }
}

/// Saga's understøttede sprog. Tilføj nye ved at extend'e enum + listen.
public enum SagaLanguage: String, CaseIterable, Sendable, Codable {
    case danish
    case english
    case tamil
    case german
    case spanish
    case french
    case italian
    case dutch
    case swedish
    case norwegian
    case finnish

    /// Saga's primære sprog ved første start. Bruger kan ændre via Settings.
    public static let `default`: SagaLanguage = .danish

    /// Sprog-kode som Canary-bridge accepterer (2-letter ISO).
    public var canaryCode: String {
        switch self {
        case .danish: return "da"
        case .english: return "en"
        case .tamil: return "ta"  // Canary supporterer ikke tamilsk — router falder til Apple
        case .german: return "de"
        case .spanish: return "es"
        case .french: return "fr"
        case .italian: return "it"
        case .dutch: return "nl"
        case .swedish: return "sv"
        case .norwegian: return "no"
        case .finnish: return "fi"
        }
    }

    /// Locale-streng som Apple Speech bruger ("ta-IN", "da-DK" osv.).
    public var appleLocale: String {
        switch self {
        case .danish: return "da-DK"
        case .english: return "en-US"
        case .tamil: return "ta-IN"
        case .german: return "de-DE"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .italian: return "it-IT"
        case .dutch: return "nl-NL"
        case .swedish: return "sv-SE"
        case .norwegian: return "nb-NO"
        case .finnish: return "fi-FI"
        }
    }

    /// Display-navn til Settings UI (på dansk).
    public var displayName: String {
        switch self {
        case .danish: return "Dansk"
        case .english: return "Engelsk"
        case .tamil: return "Tamilsk"
        case .german: return "Tysk"
        case .spanish: return "Spansk"
        case .french: return "Fransk"
        case .italian: return "Italiensk"
        case .dutch: return "Hollandsk"
        case .swedish: return "Svensk"
        case .norwegian: return "Norsk"
        case .finnish: return "Finsk"
        }
    }

    /// True hvis sprog kører via Canary (hurtigere, bedre kvalitet).
    public var usesCanary: Bool {
        MultilingualASRRouter.canarySupportedLanguages.contains(canaryCode)
    }

    /// Brugbart label til Settings: "Dansk (Canary)" eller "Tamilsk (Apple Speech)".
    public var qualityLabel: String {
        usesCanary ? "Canary — bedst kvalitet" : "Apple Speech — on-device fallback"
    }
}
