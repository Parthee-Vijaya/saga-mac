import Combine
import Foundation
import OSLog

/// Single entry-point for resten af Saga til at få Saga til at tale.
///
/// Vælger TTS-engine baseret på:
/// 1. Brugerens preferred-engine setting
/// 2. Om ElevenLabs API-key findes (kun relevant hvis preferred = elevenlabs)
/// 3. Om ElevenLabs er reachable (probet asynkront, cached)
///
/// Hvis preferred er ElevenLabs men key/netværk mangler: falder automatisk
/// tilbage til Apple TTS uden fejl. Brugeren ser ingen forskel udover lyden.
@MainActor
public final class TTSCoordinator: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "tts.coordinator")

    /// Brugerens preferred engine. Persisteres i UserDefaults.
    @Published public var preferredEngineID: String {
        didSet {
            UserDefaults.standard.set(preferredEngineID, forKey: "tts.preferredEngine")
            log.info("Preferred TTS engine: \(self.preferredEngineID, privacy: .public)")
        }
    }

    /// ElevenLabs voice-ID. Persisteres i UserDefaults (offentlig identifier — ikke secret).
    @Published public var elevenLabsVoiceID: String {
        didSet {
            UserDefaults.standard.set(elevenLabsVoiceID, forKey: "tts.elevenlabsVoiceID")
        }
    }

    /// Apple voice-identifier (fx "com.apple.voice.compact.da-DK.Sara").
    /// Persisteres i UserDefaults.
    @Published public var appleVoiceID: String {
        didSet {
            UserDefaults.standard.set(appleVoiceID, forKey: "tts.appleVoiceID")
        }
    }

    /// Senest observerede engine — bruges af UI til at vise hvilken der faktisk
    /// blev brugt (kan afvige fra preferred ved fallback).
    @Published public private(set) var lastUsedEngineID: String = ""

    /// Default rachel voice — ElevenLabs's standard. Bruger kan overstyre.
    public static let defaultElevenLabsVoiceID = "21m00Tcm4TlvDq8ikWAM"

    public init() {
        self.preferredEngineID = UserDefaults.standard.string(forKey: "tts.preferredEngine") ?? "apple"
        self.elevenLabsVoiceID = UserDefaults.standard.string(forKey: "tts.elevenlabsVoiceID")
            ?? Self.defaultElevenLabsVoiceID
        self.appleVoiceID = UserDefaults.standard.string(forKey: "tts.appleVoiceID")
            ?? (AppleTTSEngine.preferredDanishVoice() ?? "")
    }

    /// True hvis brugeren har konfigureret ElevenLabs (key er gemt i Keychain).
    public var hasElevenLabsKey: Bool {
        KeychainStore.exists(KeychainKey.elevenLabsAPI)
    }

    /// Synthesizér og afspil. Vælger engine, falder tilbage hvis preferred fejler.
    public func speak(_ text: String) async {
        let engine = selectEngine()
        do {
            try await engine.speak(text)
            lastUsedEngineID = engine.id
        } catch TTSError.cancelled {
            log.info("TTS cancelled (\(engine.id, privacy: .public))")
        } catch {
            log.warning("TTS engine \(engine.id, privacy: .public) fejlede: \(error.localizedDescription, privacy: .public)")
            // Fallback: hvis det IKKE allerede var Apple, prøv Apple
            if engine.id != "apple" {
                let fallback = AppleTTSEngine(voiceIdentifier: appleVoiceID.isEmpty ? nil : appleVoiceID)
                do {
                    try await fallback.speak(text)
                    lastUsedEngineID = fallback.id
                    log.info("Fallback til Apple TTS lykkedes")
                } catch {
                    log.error("Apple TTS fallback fejlede også: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Stop al aktiv TTS. Idempotent.
    public func stop() {
        currentEngine?.stop()
    }

    private var currentEngine: TTSEngine?

    /// Test-funktion brugt af Settings ("Sig 'Hej, jeg er Saga'" knappen).
    public func testSpeak() async {
        await speak("Hej, jeg er Saga.")
    }

    private func selectEngine() -> TTSEngine {
        let chosen = chooseEngineWithFallback()
        currentEngine = chosen
        return chosen
    }

    /// Beslutnings-logik adskilt så den kan unit-testes uden at kalde rigtig speak().
    /// Returnerer engine der skal bruges, baseret på preferred + key-tilstedeværelse.
    /// Reachability-tjek udskydes til selve speak()-kaldet — vi falder tilbage on-error.
    func chooseEngineWithFallback() -> TTSEngine {
        switch preferredEngineID {
        case "elevenlabs":
            if hasElevenLabsKey {
                return ElevenLabsTTSEngine(voiceID: elevenLabsVoiceID.isEmpty ? Self.defaultElevenLabsVoiceID : elevenLabsVoiceID)
            }
            log.info("ElevenLabs valgt men ingen API-key — falder til Apple")
            return AppleTTSEngine(voiceIdentifier: appleVoiceID.isEmpty ? nil : appleVoiceID)
        default:
            return AppleTTSEngine(voiceIdentifier: appleVoiceID.isEmpty ? nil : appleVoiceID)
        }
    }
}
