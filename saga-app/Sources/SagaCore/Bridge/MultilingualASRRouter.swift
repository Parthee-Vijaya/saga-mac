import Foundation
import OSLog

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

    private let canary: CanaryASRBridge
    private let apple: AppleSpeechBridge

    public init(canary: CanaryASRBridge, apple: AppleSpeechBridge) {
        self.canary = canary
        self.apple = apple
    }

    /// Transcribe `pcm` på det valgte sprog. Vælger Canary hvis sprog er
    /// supporteret, ellers Apple Speech med en passende locale.
    public func transcribe(pcm: CapturedAudio, language: SagaLanguage) async throws -> TranscribeResult {
        if Self.canarySupportedLanguages.contains(language.canaryCode) {
            log.info("Routing til Canary for \(language.canaryCode, privacy: .public)")
            return try await canary.transcribe(pcm: pcm, language: language.canaryCode)
        } else {
            log.info("Routing til Apple Speech for \(language.appleLocale, privacy: .public)")
            return try await apple.transcribe(pcm: pcm, languageCode: language.appleLocale)
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
