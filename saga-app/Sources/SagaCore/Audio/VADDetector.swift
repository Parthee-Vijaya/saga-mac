import Foundation

/// Voice Activity Detection — afgør om der er tale eller stilhed i audio-strømmen.
///
/// Saga bruger VAD til **auto-stop**: når brugeren har holdt hotkey nede og er
/// stoppet med at tale, kan vi automatisk afslutte recordingen i stedet for
/// at vente på key-up. Dette muliggør "tap-to-talk"-flow og reducerer dead-air
/// efter sidste ord.
///
/// Protokollen er stream-baseret: kalderen feeder normaliseret RMS-level (0...1)
/// i takt med audio-pollingen, og VAD'en svarer hver gang om der er tale eller
/// silence — plus om silence har varet længe nok til at trigge auto-stop.
public protocol VADDetector: Sendable {
    /// Reset internal state — kaldes ved start af ny recording.
    mutating func reset()

    /// Feed et nyt level-sample (normaliseret 0...1, samme skala som
    /// `AudioCapture.levelHistory`).
    ///
    /// - Returns: `.silenceTimeout` hvis brugeren har været stille længe nok
    ///   til at vi skal auto-stoppe; `.continue` ellers.
    mutating func process(level: Float, timestamp: Date) -> VADEvent
}

public enum VADEvent: Sendable, Equatable {
    case `continue`
    case silenceTimeout
}

/// Konfiguration for energy-baseret VAD.
public struct VADConfig: Sendable, Codable, Equatable {
    /// Levels under denne tærskel tælles som silence. AudioCapture
    /// normaliserer -50 dBFS → 0, -10 dBFS → ~0.8, så 0.05 svarer til
    /// roughly -47 dBFS — under typisk room-tone på indbyggede mics.
    public var silenceThreshold: Float

    /// Hvor lang sammenhængende silence der skal til før vi trigger.
    /// Default 1.2s er kompromis mellem "føles snappy" og "kort pause i
    /// tænkning skal ikke afslutte sætningen".
    public var silenceDuration: TimeInterval

    /// Minimum varighed før VAD må trigge auto-stop. Forhindrer at en
    /// kort optagelse afsluttes før brugeren har nået at sige noget.
    public var minRecordingDuration: TimeInterval

    public init(
        silenceThreshold: Float = 0.05,
        silenceDuration: TimeInterval = 1.2,
        minRecordingDuration: TimeInterval = 0.5
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.minRecordingDuration = minRecordingDuration
    }

    public static let `default` = VADConfig()
}

/// Energi-baseret VAD: tracker hvor længe det seneste sample har været under
/// silence-tærsklen, og trigger når kontinuerlig silence har varet længe nok.
///
/// Simpel og deterministisk — ingen ML-model, ingen tunge dependencies.
/// Mere avanceret VAD (Silero CoreML port, Apple Speech VAD events) kan plugges
/// ind senere via samme protocol uden at ændre AudioCapture.
public struct EnergyVAD: VADDetector {
    public let config: VADConfig
    private var firstSampleAt: Date?
    private var silenceStartedAt: Date?
    private var hasFiredTimeout: Bool

    public init(config: VADConfig = .default) {
        self.config = config
        self.firstSampleAt = nil
        self.silenceStartedAt = nil
        self.hasFiredTimeout = false
    }

    public mutating func reset() {
        firstSampleAt = nil
        silenceStartedAt = nil
        hasFiredTimeout = false
    }

    public mutating func process(level: Float, timestamp: Date) -> VADEvent {
        if firstSampleAt == nil {
            firstSampleAt = timestamp
        }
        // Afvent min-duration før vi overhovedet overvejer at trigge.
        guard let start = firstSampleAt,
              timestamp.timeIntervalSince(start) >= config.minRecordingDuration else {
            return .continue
        }

        if level < config.silenceThreshold {
            if silenceStartedAt == nil {
                silenceStartedAt = timestamp
            }
            if let silenceStart = silenceStartedAt,
               timestamp.timeIntervalSince(silenceStart) >= config.silenceDuration,
               !hasFiredTimeout {
                hasFiredTimeout = true
                return .silenceTimeout
            }
        } else {
            // Tale igen — nulstil silence-window
            silenceStartedAt = nil
        }
        return .continue
    }
}
