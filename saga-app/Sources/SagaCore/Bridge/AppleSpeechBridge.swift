@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// On-device transcribe via Apple's `SFSpeechRecognizer`.
///
/// Bruges som ASR-backend for sprog Canary-1b-v2 ikke understøtter — typisk
/// tamilsk (`ta-IN`/`ta-LK`) og andre ikke-EU-sprog. Apple's recognizer er
/// langsommere og mindre præcis end Canary for de sprog Canary supporterer,
/// men dækker 50+ sprog inkl. tamilsk.
///
/// Kører fuldt **on-device** når `requiresOnDeviceRecognition = true` (kræver
/// at brugerens Mac har sproget downloaded i System Settings → Apple
/// Intelligence & Siri → Speech Languages). Hvis ikke, falder vi tilbage til
/// cloud-recognition som er hurtigere men sender audio til Apple.
public final class AppleSpeechBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "apple-speech")

    public init() {}

    /// Sprog Saga eksponerer i Settings — vi viser kun dem Apple faktisk
    /// supporterer. Tjek runtime via `SFSpeechRecognizer.supportedLocales()`.
    public static let supportedLanguageCodes: [String] = [
        "ta-IN", "ta-LK",  // Tamil (Indien, Sri Lanka)
        "en-US", "en-GB",  // Engelsk
        "da-DK",           // Dansk (vi foretrækker normalt Canary, men fallback)
        "de-DE", "fr-FR", "es-ES", "it-IT", "nl-NL",
        "sv-SE", "nb-NO", "fi-FI",
        "ja-JP", "ko-KR", "zh-CN", "zh-TW",
        "hi-IN", "bn-IN", "te-IN", "ml-IN",
        "ar-SA", "tr-TR", "pl-PL", "ru-RU",
    ]

    /// Transcribe en PCM-buffer via SFSpeechRecognizer. Asynkron — returnerer
    /// når recognition er færdig (final result eller error).
    public func transcribe(pcm: CapturedAudio, languageCode: String) async throws -> TranscribeResult {
        let locale = Locale(identifier: languageCode)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            log.error("SFSpeechRecognizer ikke tilgængelig for \(languageCode, privacy: .public)")
            throw AppleSpeechError.recognizerUnavailable(languageCode)
        }

        // Find PCM-buffer som AVAudioPCMBuffer for at fodre recognizer
        let buffer = try makeAudioBuffer(from: pcm)

        // Setup request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false  // vi vil have final result, ikke streaming
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation

        let started = Date()
        log.info("AppleSpeech transcribe start: \(languageCode, privacy: .public), \(pcm.duration, privacy: .public)s")

        // Kør recognition. ResumeGuard er thread-safe så continuation ikke
        // kan resume'es flere gange (race mellem result-callback og timeout).
        let text = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let guardLock = ResumeGuard()
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if guardLock.tryConsume() {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                let transcript = result.bestTranscription.formattedString
                if guardLock.tryConsume() {
                    cont.resume(returning: transcript)
                }
            }

            // Append buffer + signal end-of-audio
            request.append(buffer)
            request.endAudio()

            // Hvis recognition aldrig fyrer (sjælden race condition), timeout efter 60s
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                if guardLock.tryConsume() {
                    task.cancel()
                    cont.resume(throwing: AppleSpeechError.timeout)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(started)
        log.info("AppleSpeech transcribe done: \(text.count, privacy: .public) chars, \(elapsed, privacy: .public)s")

        return TranscribeResult(
            text: text,
            durationMs: Int(pcm.duration * 1000),
            inferenceMs: Int(elapsed * 1000),
            rtf: pcm.duration > 0 ? elapsed / pcm.duration : 0
        )
    }

    /// Konverter Saga's `CapturedAudio` (Float32 PCM @ 16kHz mono) til
    /// `AVAudioPCMBuffer` som SFSpeechRecognizer kan fodres.
    private func makeAudioBuffer(from pcm: CapturedAudio) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(pcm.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw AppleSpeechError.bufferCreationFailed
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(pcm.samples.count)
        ) else {
            throw AppleSpeechError.bufferCreationFailed
        }
        buffer.frameLength = AVAudioFrameCount(pcm.samples.count)
        if let channelData = buffer.floatChannelData?[0] {
            pcm.samples.withUnsafeBufferPointer { src in
                channelData.update(from: src.baseAddress!, count: pcm.samples.count)
            }
        }
        return buffer
    }
}

/// Thread-safe one-shot guard. tryConsume() returnerer true præcis én gang.
/// Forhindrer at en CheckedContinuation resumes flere gange ved race mellem
/// recognition-callback og timeout-fallback.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func tryConsume() -> Bool {
        lock.withLock {
            if consumed { return false }
            consumed = true
            return true
        }
    }
}

public enum AppleSpeechError: Error, LocalizedError {
    case recognizerUnavailable(String)
    case bufferCreationFailed
    case timeout

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let code):
            return "Apple Speech kan ikke bruge sproget '\(code)'. Tilføj det i System Settings → Apple Intelligence & Siri → Speech Languages."
        case .bufferCreationFailed:
            return "Kunne ikke konvertere audio til Apple Speech-format."
        case .timeout:
            return "Apple Speech timeout — recognition tog over 60 sekunder."
        }
    }
}
