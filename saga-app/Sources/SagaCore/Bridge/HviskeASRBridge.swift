import Foundation
import OSLog

/// Stub-bridge til Hviske-v5.3 (dansk Conformer ASR fra syv.ai).
///
/// API matcher `CanaryASRBridge` så `MultilingualASRRouter` kan vælge
/// mellem dem baseret på `SagaController.preferredDanishEngine`.
///
/// **Status**: Stub. Returnerer altid `.error(...)` state og kaster
/// `ASRBridgeError.notReady` ved transcribe. Erstattes med rigtig
/// implementering når `hviske-coreml` projektet (sideprojekt, ~5-10 dage)
/// har produceret CoreML mlpackages og en `HviskeKit` Swift Package.
///
/// Indtil da er Hviske-mode synlig i Settings → Voice som "Kommer snart".
/// Bruger der prøver at transkribere på Hviske får en fejl + falder tilbage
/// til Canary via router-logikken.
///
/// Se `~/Desktop/Claude/projekter/aktive/hviske-coreml/HANDOFF.md` for
/// implementations-roadmap (F1-F8).
public final class HviskeASRBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "hviske")

    public init() {}

    /// Hviske er aldrig "klar" indtil F8 i hviske-coreml-projektet er done.
    public var state: ASRState {
        .error("Hviske er ikke installeret endnu — bruger Canary i mellemtiden")
    }

    public var device: String { "ANE+GPU (når installeret)" }

    public var modelLabel: String { "Hviske-v5.3 (Conformer 2B) — kommer snart" }

    public var isReady: Bool { false }

    /// No-op load. Når hviske-coreml er færdig, erstattes denne med
    /// faktisk model-load via HviskeKit.
    public func load() async {
        log.info("HviskeASRBridge.load() kaldt — stub, ingen handling")
    }

    /// Kaster `notReady`. MultilingualASRRouter fanger fejlen og falder
    /// tilbage til Canary for dansk når preferredDanishEngine = .hviske
    /// men bridgen ikke er klar.
    public func transcribe(pcm: CapturedAudio, language: String = "da") async throws -> TranscribeResult {
        log.warning("HviskeASRBridge.transcribe kaldt før implementation — returnerer notReady")
        throw ASRBridgeError.notReady
    }
}
