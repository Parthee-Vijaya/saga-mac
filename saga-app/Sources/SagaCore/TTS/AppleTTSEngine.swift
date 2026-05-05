@preconcurrency import AVFoundation
import Foundation
import OSLog

/// AVSpeechSynthesizer-baseret TTS. Offline, gratis, robotisk.
/// Default-engine når ingen ElevenLabs-key er konfigureret eller netværk er væk.
public final class AppleTTSEngine: TTSEngine, @unchecked Sendable {
    public let id = "apple"
    public let displayName = "Apple (offline)"
    public let requiresNetwork = false
    public let requiresAPIKey = false

    private let log = Logger(subsystem: "dk.parthee.saga", category: "tts.apple")
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var currentContinuation: CheckedContinuation<Void, Error>?
    private let delegate: SpeechDelegate

    /// Foretrukken voice-identifier. nil = lad systemet vælge.
    /// Default forsøger dansk Sara hvis tilgængelig på systemet.
    public let voiceIdentifier: String?

    public init(voiceIdentifier: String? = nil) {
        let resolved = voiceIdentifier ?? Self.preferredDanishVoice()
        self.voiceIdentifier = resolved
        self.delegate = SpeechDelegate()
        delegate.engine = self
        synthesizer.delegate = delegate
    }

    public func speak(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Hvis allerede taler, stop først
        if synthesizer.isSpeaking {
            stop()
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voiceId = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "da-DK")
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        log.info("Apple TTS speak (\(trimmed.count, privacy: .public) chars)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            currentContinuation = continuation
            lock.unlock()
            synthesizer.speak(utterance)
        }
    }

    public func stop() {
        lock.lock()
        let cont = currentContinuation
        currentContinuation = nil
        lock.unlock()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        cont?.resume(throwing: TTSError.cancelled)
    }

    fileprivate func finish(error: Error? = nil) {
        lock.lock()
        let cont = currentContinuation
        currentContinuation = nil
        lock.unlock()
        if let error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume()
        }
    }

    /// Find en passende dansk stemme på systemet. Foretrukne (i prioritet):
    /// 1. Sara (compact)
    /// 2. enhanced/premium dansk
    /// 3. enhver da-DK
    public static func preferredDanishVoice() -> String? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let danish = voices.filter { $0.language == "da-DK" }
        if let sara = danish.first(where: { $0.identifier.contains("Sara") }) {
            return sara.identifier
        }
        if let premium = danish.first(where: { $0.quality == .premium }) {
            return premium.identifier
        }
        if let enhanced = danish.first(where: { $0.quality == .enhanced }) {
            return enhanced.identifier
        }
        return danish.first?.identifier
    }

    /// Liste af tilgængelige danske stemmer på systemet — bruges af Settings-picker.
    public static func availableDanishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "da-DK" }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    weak var engine: AppleTTSEngine?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        engine?.finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // .cancelled blev allerede resumed i stop() — gør ikke noget her
    }
}
