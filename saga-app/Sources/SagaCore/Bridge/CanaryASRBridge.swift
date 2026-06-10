import CanaryKit
import CoreML
import Foundation
import OSLog

/// Native CoreML ASR via CanaryKit (NVIDIA Canary-1b-v2 → CoreML).
///
/// Erstatter den oprindelige HviskeBridge + Python-sidecar. Modellen er bundlet
/// som ``.mlpackage`` i Saga.app/Contents/Resources/mlpackage/. Cold-start: ~10s
/// første transcribe. Warm RTF: ~0.15 (sub-realtime, FP16 og int4 identiske).
///
/// Hviske-coreml planlægges som drop-in-erstatning senere (~10 dages konvertering)
/// — samme interface, bedre dansk-kvalitet (Hviske 14% WER vs Canary ~16%).
public final class CanaryASRBridge: DanishASRBridging, @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "canary")

    private let queue = DispatchQueue(label: "dk.parthee.saga.canary")
    private var _asr: CanaryASR?
    private var _state: ASRState = .uninitialized
    private var _device: String = "ANE+GPU"
    private var _useInt4: Bool = true

    public init() {}

    public var state: ASRState { queue.sync { _state } }
    public var device: String { queue.sync { _device } }
    public var modelLabel: String {
        queue.sync { _useInt4 ? "Canary-1b-v2 (int4)" : "Canary-1b-v2 (FP16)" }
    }
    public var isReady: Bool {
        if case .ready = state { return true } else { return false }
    }

    public func load(useInt4: Bool = true) async {
        queue.sync {
            _useInt4 = useInt4
            _state = .loading
        }

        let modelsDir: URL
        do {
            modelsDir = try locateModelsDirectory()
        } catch {
            log.error("Kunne ikke finde mlpackage: \(error.localizedDescription)")
            queue.sync { _state = .error(error.localizedDescription) }
            return
        }

        log.info("Loader CanaryASR fra \(modelsDir.path) (int4=\(useInt4))")

        // Run CanaryASR.init på en baggrundsqueue (CanaryASR er ikke Sendable så
        // vi blokker en serial queue i stedet for at krydse actor-grænse via Task)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(); return }
                let t0 = Date()
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all
                    let asr = try CanaryASR(modelsDir: modelsDir, useInt4: useInt4, modelConfiguration: config)
                    let elapsed = Date().timeIntervalSince(t0)
                    self.log.info("CanaryASR loaded på \(String(format: "%.1f", elapsed))s")
                    self._asr = asr
                    self._state = .ready

                    // Warmup på samme queue (efter load er klar)
                    let wt0 = Date()
                    asr.warmUp(sourceLang: "da")
                    self.log.info("Warmup: \(String(format: "%.1f", Date().timeIntervalSince(wt0)))s")
                } catch {
                    self.log.error("CanaryASR.init fejlede: \(error.localizedDescription)")
                    self._state = .error(error.localizedDescription)
                }
                cont.resume()
            }
        }
    }

    public func transcribe(pcm: CapturedAudio, language: String = "da") async throws -> TranscribeResult {
        guard pcm.duration >= 0.1 else { throw ASRBridgeError.audioTooShort }

        let durMs = Int(pcm.duration * 1000)
        let samples = pcm.samples

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TranscribeResult, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: ASRBridgeError.notReady)
                    return
                }
                guard let asr = self._asr else {
                    cont.resume(throwing: ASRBridgeError.notReady)
                    return
                }
                let t0 = Date()
                do {
                    let text = try asr.transcribe(pcm: samples, sourceLang: language, targetLang: language, pnc: true)
                    let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
                    let rtf = durMs > 0 ? Double(elapsedMs) / Double(durMs) : 0
                    self.log.info("Transcribe ok: \(durMs)ms audio → \(elapsedMs)ms inference (rtf \(String(format: "%.3f", rtf)))")
                    cont.resume(returning: TranscribeResult(
                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        durationMs: durMs,
                        inferenceMs: elapsedMs,
                        rtf: rtf
                    ))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func locateModelsDirectory() throws -> URL {
        // 1. Bundled i Saga.app/Contents/Resources/mlpackage/
        if let bundled = Bundle.main.url(forResource: "mlpackage", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("CanaryEncoder.mlpackage").path) {
            return bundled
        }

        // 2. Slim-DMG path: ~/Library/Application Support/Saga/Models/mlpackage/
        //    Skrevet af ModelDownloader når brugeren har downloaded modellen.
        let appSupport = ModelStorage.modelsDirectory
        if FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("CanaryEncoder.mlpackage").path) {
            return appSupport
        }

        // 3. Env-override (test/CI)
        if let envPath = ProcessInfo.processInfo.environment["SAGA_CANARY_MODELS_DIR"] {
            let url = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("CanaryEncoder.mlpackage").path) {
                return url
            }
        }

        // 4. Dev-fallback: ../../canary-coreml/models/mlpackage relativt til exec
        let exec = Bundle.main.executableURL ?? URL(fileURLWithPath: ".")
        let devCandidate = exec
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("canary-coreml/models/mlpackage")
        if FileManager.default.fileExists(atPath: devCandidate.appendingPathComponent("CanaryEncoder.mlpackage").path) {
            return devCandidate
        }

        // 5. Hardcoded dev-fallback til Parthee's setup. Prøver flere placeringer
        // fordi projekt-mapperne er splittet i aktive/ og arkiv/ — gamle paths
        // uden disse kan stadig findes hvis nogen kører en pre-flyttet checkout.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeCandidates = [
            "Desktop/Claude/projekter/aktive/canary-coreml/models/mlpackage",
            "Desktop/Claude/projekter/arkiv/canary-coreml/models/mlpackage",
            "Desktop/Claude/projekter/canary-coreml/models/mlpackage",
            "projekter/canary-coreml/models/mlpackage",
        ]
        for candidate in homeCandidates {
            let url = home.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("CanaryEncoder.mlpackage").path) {
                return url
            }
        }

        throw ASRBridgeError.modelsNotFound
    }
}

public enum ASRState: Equatable, Sendable {
    case uninitialized
    case loading
    case ready
    case error(String)

    public var label: String {
        switch self {
        case .uninitialized: return "Ikke loaded"
        case .loading: return "Indlæser CoreML…"
        case .ready: return "Klar"
        case .error(let msg): return "Fejl: \(msg)"
        }
    }

    public var isHappy: Bool {
        if case .ready = self { return true } else { return false }
    }
}

public enum ASRBridgeError: Error, LocalizedError {
    case notReady
    case audioTooShort
    case modelsNotFound

    public var errorDescription: String? {
        switch self {
        case .notReady: return "ASR-modellen er ikke loaded endnu"
        case .audioTooShort: return "Optagelsen er for kort (<0.1s)"
        case .modelsNotFound:
            return "CanaryKit-modeller kunne ikke findes. Kør canary-coreml/python pipeline og kopier mlpackage/ til canary-coreml/models/."
        }
    }
}
