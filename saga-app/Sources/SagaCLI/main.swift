@preconcurrency import AVFoundation
import CanaryKit
import CoreML
import Foundation
import WhisperKit

// saga-cli — minimal command-line transcribe-værktøj.
//
// Bruger samme CanaryKit + WhisperKit-deps som Saga.app, men uden UI/HUD
// /mode-routing. Tager en audio-fil og udskriver transkripten til stdout.
//
// Brug:
//     saga-cli <audio.wav> [--engine canary|hviske] [--language da]
//     saga-cli ~/sample.wav --engine hviske > transcript.txt
//
// For batch-jobs:
//     for f in *.wav; do saga-cli "$f" --engine canary >> all.txt; done

struct SagaCLI {
    static func run() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printUsage()
            exit(EXIT_FAILURE)
        }

        let audioPath = args[1]
        let engine = parseFlag(args, name: "--engine", default: "canary")
        let language = parseFlag(args, name: "--language", default: "da")
        let modelsPath = parseFlag(args, name: "--models", default: defaultModelsPath(for: engine))

        if audioPath == "-h" || audioPath == "--help" {
            printUsage()
            exit(EXIT_SUCCESS)
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            stderr("Fejl: audio-fil ikke fundet: \(audioPath)")
            exit(EXIT_FAILURE)
        }

        let pcm: [Float]
        do {
            pcm = try loadPCM(from: audioURL)
        } catch {
            stderr("Fejl ved læsning af audio: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }

        do {
            let text: String
            switch engine {
            case "canary":
                text = try await transcribeCanary(pcm: pcm, language: language, modelsDir: modelsPath)
            case "hviske":
                text = try await transcribeHviske(pcm: pcm, language: language, modelsDir: modelsPath)
            default:
                stderr("Ukendt engine '\(engine)'. Brug canary eller hviske.")
                exit(EXIT_FAILURE)
            }
            print(text)
        } catch {
            stderr("Transcribe fejlede: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }

    // MARK: - Engines

    static func transcribeCanary(pcm: [Float], language: String, modelsDir: String) async throws -> String {
        let url = URL(fileURLWithPath: modelsDir)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let asr = try CanaryASR(modelsDir: url, useInt4: false, modelConfiguration: config)
        return try asr.transcribe(pcm: pcm, sourceLang: language, targetLang: language, pnc: true)
    }

    static func transcribeHviske(pcm: [Float], language: String, modelsDir: String) async throws -> String {
        let config = WhisperKitConfig(modelFolder: modelsDir, load: true)
        let pipe = try await WhisperKit(config)
        let results = try await pipe.transcribe(
            audioArray: pcm,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: language,
                temperature: 0.0,
                usePrefillPrompt: true,
                skipSpecialTokens: true
            )
        )
        return results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Helpers

    static func loadPCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw NSError(domain: "saga-cli", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kan ikke lave audio-converter"])
        }

        let inputBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inputBuf)

        let outputCapacity = AVAudioFrameCount(Double(file.length) * 16000.0 / file.processingFormat.sampleRate) + 1024
        let outputBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity)!

        var error: NSError?
        let consumed = ConsumedFlag()
        let status = converter.convert(to: outputBuf, error: &error) { _, status in
            if consumed.value {
                status.pointee = .endOfStream
                return nil
            }
            consumed.value = true
            status.pointee = .haveData
            return inputBuf
        }

        if status == .error || error != nil {
            throw error ?? NSError(domain: "saga-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio-conversion fejlede"])
        }

        guard let channel = outputBuf.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuf.frameLength)))
    }

    static func parseFlag(_ args: [String], name: String, default defaultValue: String) -> String {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else {
            return defaultValue
        }
        return args[idx + 1]
    }

    static func defaultModelsPath(for engine: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch engine {
        case "canary":
            return "\(home)/Desktop/Claude/projekter/aktive/canary-coreml/models/mlpackage"
        case "hviske":
            return "\(home)/Desktop/Claude/projekter/aktive/hviske-coreml/models/whisperkit/syvai_hviske-v3"
        default:
            return ""
        }
    }

    static func printUsage() {
        let usage = """
        saga-cli — kommandolinje-transcribe via CanaryKit eller Hviske/WhisperKit

        Brug:
            saga-cli <audio.wav> [options]

        Options:
            --engine <canary|hviske>     Default: canary
            --language <da|en|...>       ISO-639-1 sprog-kode. Default: da
            --models <path>              Override sti til mlpackage-mappe.
                                         Default: ~/Desktop/Claude/projekter/aktive/{canary,hviske}-coreml/models/...

        Eksempler:
            saga-cli sample.wav
            saga-cli ~/audio/møde.m4a --engine hviske
            saga-cli interview.wav --language en > transcript.txt

        Output: ren tekst på stdout. Fejl på stderr.
        """
        FileHandle.standardError.write(Data((usage + "\n").utf8))
    }

    static func stderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Reference-wrapper omkring Bool for at kunne mutere fra @Sendable-closure
/// uden at SwiftBuild-strict-concurrency klager.
final class ConsumedFlag: @unchecked Sendable {
    var value: Bool = false
}

await SagaCLI.run()
