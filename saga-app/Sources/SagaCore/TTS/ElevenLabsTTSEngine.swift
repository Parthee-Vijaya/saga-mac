@preconcurrency import AVFoundation
import Foundation
import OSLog

/// ElevenLabs TTS via deres `text-to-speech` HTTP-endpoint.
///
/// Sender Saga's reply-tekst over HTTPS til ElevenLabs servere som returnerer en
/// MP3-stream. Decoded af AVAudioPlayer. Premium kvalitet, latency ~300-800ms
/// til første byte.
///
/// **Privacy-bemærkning**: Den fulde svar-tekst forlader maskinen og sendes til
/// ElevenLabs cloud. Saga's audio (input) gør det IKKE — kun den genererede tekst.
/// Brugeren skal eksplicit aktivere ElevenLabs i Settings.
public final class ElevenLabsTTSEngine: TTSEngine, @unchecked Sendable {
    public let id = "elevenlabs"
    public let displayName = "ElevenLabs (cloud)"
    public let requiresNetwork = true
    public let requiresAPIKey = true

    private let log = Logger(subsystem: "dk.parthee.saga", category: "tts.elevenlabs")
    private let session: URLSession
    private let lock = NSLock()
    private var currentPlayer: AVAudioPlayer?
    private var currentTask: URLSessionDataTask?
    private let delegate: PlayerDelegate

    /// Voice-ID — ElevenLabs identifier (fx "21m00Tcm4TlvDq8ikWAM" for Rachel).
    /// Default voice-IDer kan listes via /v1/voices endpointet.
    public let voiceID: String

    /// Model-ID. "eleven_multilingual_v2" understøtter dansk.
    public let modelID: String

    public init(
        voiceID: String,
        modelID: String = "eleven_multilingual_v2",
        timeoutInterval: TimeInterval = 30
    ) {
        self.voiceID = voiceID
        self.modelID = modelID
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2
        self.session = URLSession(configuration: config)
        self.delegate = PlayerDelegate()
        delegate.engine = self
    }

    public func speak(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let apiKey = KeychainStore.read(KeychainKey.elevenLabsAPI), !apiKey.isEmpty else {
            throw TTSError.missingAPIKey
        }

        // Hvis vi allerede afspiller, stop først
        stop()

        let mp3 = try await downloadMP3(text: trimmed, apiKey: apiKey)
        log.info("ElevenLabs MP3 modtaget (\(mp3.count, privacy: .public) bytes)")

        try await playMP3(mp3)
    }

    public func stop() {
        lock.lock()
        let task = currentTask
        let player = currentPlayer
        currentTask = nil
        currentPlayer = nil
        lock.unlock()

        task?.cancel()
        player?.stop()
    }

    private func downloadMP3(text: String, apiKey: String) async throws -> Data {
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"
        guard let url = URL(string: urlString) else {
            throw TTSError.invalidResponse(statusCode: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                log.warning("ElevenLabs HTTP \(http.statusCode) — \(String(data: data, encoding: .utf8) ?? "?", privacy: .public)")
                throw TTSError.invalidResponse(statusCode: http.statusCode)
            }
            return data
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw TTSError.cancelled
        } catch let ttsError as TTSError {
            throw ttsError
        } catch {
            throw TTSError.networkFailure(underlying: error)
        }
    }

    @MainActor
    private func playMP3(_ data: Data) async throws {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = delegate
            player.prepareToPlay()

            lock.withLock {
                currentPlayer = player
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                if !player.play() {
                    continuation.resume(throwing: TTSError.audioPlaybackFailed(underlying: NSError(
                        domain: "Saga.TTS", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returnerede false"]
                    )))
                }
            }
        } catch let ttsError as TTSError {
            throw ttsError
        } catch {
            throw TTSError.audioPlaybackFailed(underlying: error)
        }
    }
}

/// Liste-element fra ElevenLabs /v1/voices. Bruges til Settings-voice-picker.
public struct ElevenLabsVoice: Sendable, Hashable, Identifiable {
    public let voiceID: String
    public let name: String
    public let labels: [String: String]

    public var id: String { voiceID }

    /// Hvis labels indeholder language-info, returnér den. Ellers nil.
    public var language: String? {
        labels["language"]
    }
}

/// Hjælpe-funktion til at hente listen af tilgængelige stemmer fra ElevenLabs.
/// Brugt af Settings-tab. Returnerer tom liste på fejl frem for at throw.
public enum ElevenLabsVoiceCatalog {
    public static func fetch(apiKey: String, timeout: TimeInterval = 10) async -> [ElevenLabsVoice] {
        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/voices") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let voices = json["voices"] as? [[String: Any]] else {
                return []
            }
            return voices.compactMap { dict -> ElevenLabsVoice? in
                guard let voiceID = dict["voice_id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                let labels = dict["labels"] as? [String: String] ?? [:]
                return ElevenLabsVoice(voiceID: voiceID, name: name, labels: labels)
            }
        } catch {
            return []
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    weak var engine: ElevenLabsTTSEngine?
    var continuation: CheckedContinuation<Void, Error>?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let cont = continuation
        continuation = nil
        if flag {
            cont?.resume()
        } else {
            cont?.resume(throwing: TTSError.audioPlaybackFailed(underlying: NSError(
                domain: "Saga.TTS", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Playback afsluttede med flag=false"]
            )))
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let cont = continuation
        continuation = nil
        cont?.resume(throwing: TTSError.audioPlaybackFailed(underlying: error ?? NSError(
            domain: "Saga.TTS", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "MP3-decode fejlede"]
        )))
    }
}
