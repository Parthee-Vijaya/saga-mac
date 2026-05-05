import Foundation

/// Text-to-Speech-protokol som dækker både on-device og cloud-baserede engines.
///
/// Saga har pt. to implementationer:
/// - `AppleTTSEngine` — AVSpeechSynthesizer, offline, default
/// - `ElevenLabsTTSEngine` — cloud, premium kvalitet, opt-in
///
/// `TTSCoordinator` vælger imellem dem ved runtime baseret på key + reachability.
public protocol TTSEngine: Sendable {
    /// Identifier til persistens og UI-display.
    var id: String { get }

    /// Et menneske-læsbart navn vist i Settings-picker.
    var displayName: String { get }

    /// True hvis denne engine kræver netværksforbindelse.
    var requiresNetwork: Bool { get }

    /// True hvis denne engine kræver bruger-konfiguration (API-key) for at virke.
    var requiresAPIKey: Bool { get }

    /// Synthesizér og afspil. Returnerer når playback er færdig (eller stoppet via `stop()`).
    /// Throws hvis engine ikke kan operere (manglende key, netværksfejl, etc.).
    func speak(_ text: String) async throws

    /// Afbryd current playback. Idempotent.
    func stop()
}

/// Fejl der kan opstå ved TTS-operationer.
public enum TTSError: Error, LocalizedError {
    case engineUnavailable(reason: String)
    case missingAPIKey
    case networkFailure(underlying: Error)
    case invalidResponse(statusCode: Int)
    case audioPlaybackFailed(underlying: Error)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason):
            return "TTS-engine ikke tilgængelig: \(reason)"
        case .missingAPIKey:
            return "API-key mangler i Settings → Companion."
        case .networkFailure(let err):
            return "Netværksfejl: \(err.localizedDescription)"
        case .invalidResponse(let code):
            return "TTS-server svarede med fejl (\(code))."
        case .audioPlaybackFailed(let err):
            return "Audio-playback fejlede: \(err.localizedDescription)"
        case .cancelled:
            return "TTS afbrudt."
        }
    }
}
