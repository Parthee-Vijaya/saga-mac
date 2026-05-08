import CoreML
import Foundation
import OSLog
import WhisperKit

/// Bridge til Hviske-v3 (Whisper-large-v3-turbo finetune fra syv.ai),
/// brugt som premium dansk-engine.
///
/// Bruger Argmax's WhisperKit direkte — vi inline'r logikken her i stedet
/// for at gå via en separat `HviskeKit` Swift Package fordi SPM får path-
/// collision når både canary-coreml/swift og hviske-coreml/swift er deps
/// (samme `swift`-mappenavn). hviske-coreml er stadig single-source-of-
/// truth for konvertering + mlpackages; vi kopierer bare API'et hertil.
///
/// API matcher CanaryASRBridge så MultilingualASRRouter kan vælge mellem
/// dem baseret på SagaController.preferredDanishEngine.
public final class HviskeASRBridge: @unchecked Sendable {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "hviske")

    private let queue = DispatchQueue(label: "dk.parthee.saga.hviske")
    private var _pipe: WhisperKit?
    private var _state: ASRState = .uninitialized

    public init() {}

    public var state: ASRState { queue.sync { _state } }

    public var device: String { "ANE+GPU" }

    public var modelLabel: String { "Hviske-v3 (Whisper-large-v3-turbo)" }

    public var isReady: Bool {
        if case .ready = state { return true } else { return false }
    }

    /// Indlæs WhisperKit lazy med Hviske-v3 mlpackages. Kaldes af
    /// SagaController når brugeren skifter til Hviske som
    /// preferredDanishEngine. Idempotent.
    public func load() async {
        if case .ready = state { return }
        if case .loading = state { return }

        queue.sync { _state = .loading }

        let sourceDir: URL
        do {
            sourceDir = try locateModelsDirectory()
        } catch {
            log.error("Hviske mlpackages mangler: \(error.localizedDescription, privacy: .public)")
            queue.sync { _state = .error("Hviske-modeller ikke fundet — kør hviske-coreml/python/v3_convert.py") }
            return
        }

        // WhisperKit kan ikke loade .mlpackage direkte — de skal kompileres
        // til .mlmodelc først. Vi pre-compiler én gang og cacher i App
        // Support, så subsequent loads er instant.
        let compiledDir: URL
        do {
            compiledDir = try await compileModelsIfNeeded(sourceDir: sourceDir)
        } catch {
            log.error("Hviske compile fejlede: \(error.localizedDescription, privacy: .public)")
            queue.sync { _state = .error("Kunne ikke kompilere Hviske-modeller: \(error.localizedDescription)") }
            return
        }

        log.info("Loader Hviske via WhisperKit fra \(compiledDir.path, privacy: .public)")
        let t0 = Date()
        do {
            let config = WhisperKitConfig(
                modelFolder: compiledDir.path,
                load: true
            )
            let pipe = try await WhisperKit(config)
            queue.sync {
                _pipe = pipe
                _state = .ready
            }
            let elapsed = Date().timeIntervalSince(t0)
            log.info("Hviske loaded på \(String(format: "%.1f", elapsed))s")
        } catch {
            log.error("WhisperKit init fejlede: \(error.localizedDescription, privacy: .public)")
            queue.sync { _state = .error(error.localizedDescription) }
        }
    }

    /// Kompiler hver .mlpackage til .mlmodelc og kopier alle nødvendige
    /// non-model-filer (tokenizer, config) til cache-mappen. Idempotent —
    /// springer over hvis cache allerede har de compiled-filer.
    /// Returnerer URL til compiled-mappen som WhisperKit kan loade.
    private func compileModelsIfNeeded(sourceDir: URL) async throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheDir = appSupport.appendingPathComponent("Saga/HviskeCompiled", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let mlpackageNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        for name in mlpackageNames {
            let source = sourceDir.appendingPathComponent("\(name).mlpackage")
            let dest = cacheDir.appendingPathComponent("\(name).mlmodelc")

            if FileManager.default.fileExists(atPath: dest.path) {
                continue  // allerede kompileret
            }
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw HviskeBridgeError.mlpackageMissing(name)
            }

            log.info("Kompilerer \(name).mlpackage → mlmodelc (kan tage 10-30s første gang)")
            let t0 = Date()
            let compiledURL = try await MLModel.compileModel(at: source)
            // compileModel returnerer en path i temp-mappen — flyt den til cache.
            // Hvis dest eksisterer (race), slet og prøv igen.
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: compiledURL, to: dest)
            let elapsed = Date().timeIntervalSince(t0)
            log.info("\(name) compiled på \(String(format: "%.1f", elapsed))s")
        }

        // Kopier WhisperKit's nødvendige sidekar-filer (tokenizer, configs).
        // Vi rør ikke ved dem hvis de allerede findes — så subsequent boots
        // er instant.
        let sidecarFiles = [
            "tokenizer.json", "config.json", "generation_config.json",
            "added_tokens.json", "merges.txt", "normalizer.json",
            "preprocessor_config.json", "tokenizer_config.json", "vocab.json",
        ]
        for name in sidecarFiles {
            let source = sourceDir.appendingPathComponent(name)
            let dest = cacheDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path),
               !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: source, to: dest)
            }
        }

        return cacheDir
    }

    /// Transkribér 16 kHz mono PCM Float32. Måler inference-tid for at
    /// returnere TranscribeResult med RTF — matcher CanaryASRBridge.
    public func transcribe(pcm: CapturedAudio, language: String = "da") async throws -> TranscribeResult {
        guard pcm.duration >= 0.1 else { throw ASRBridgeError.audioTooShort }
        let pipe = queue.sync { _pipe }
        guard let pipe else { throw ASRBridgeError.notReady }

        let durMs = Int(pcm.duration * 1000)
        let t0 = Date()
        let results = try await pipe.transcribe(
            audioArray: pcm.samples,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: "da",
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true
            )
        )
        let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
        let rtf = durMs > 0 ? Double(elapsedMs) / Double(durMs) : 0
        let text = results.first?.text ?? ""
        log.info("Hviske transcribe: \(durMs)ms audio → \(elapsedMs)ms inference (rtf \(String(format: "%.3f", rtf)))")

        return TranscribeResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            durationMs: durMs,
            inferenceMs: elapsedMs,
            rtf: rtf
        )
    }

    /// Find Hviske mlpackage-mappen. Søsterprojektets default-output ligger
    /// i `models/whisperkit/syvai_hviske-v3/` ved siden af Saga-repo'et.
    /// Kan overrides via SAGA_HVISKE_MODELS_DIR-env.
    private func locateModelsDirectory() throws -> URL {
        // 1. Env-override (test/CI)
        if let envPath = ProcessInfo.processInfo.environment["SAGA_HVISKE_MODELS_DIR"] {
            let url = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlpackage").path) {
                return url
            }
        }

        // 2. Bundled (når vi senere ship'er Hviske med Saga.app)
        if let bundled = Bundle.main.url(forResource: "hviske-mlpackage", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("AudioEncoder.mlpackage").path) {
            return bundled
        }

        // 3. Søsterprojekt: ~/Desktop/Claude/projekter/aktive/hviske-coreml/models/whisperkit/syvai_hviske-v3
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "Desktop/Claude/projekter/aktive/hviske-coreml/models/whisperkit/syvai_hviske-v3",
            "Desktop/Claude/projekter/arkiv/hviske-coreml/models/whisperkit/syvai_hviske-v3",
            "projekter/hviske-coreml/models/whisperkit/syvai_hviske-v3",
        ]
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlpackage").path) {
                return url
            }
        }

        throw ASRBridgeError.modelsNotFound
    }
}

public enum HviskeBridgeError: Error, LocalizedError {
    case mlpackageMissing(String)

    public var errorDescription: String? {
        switch self {
        case .mlpackageMissing(let name):
            return "Hviske \(name).mlpackage mangler — kør hviske-coreml/python/v3_convert.py"
        }
    }
}
