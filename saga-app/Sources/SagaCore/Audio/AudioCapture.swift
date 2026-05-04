@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Capture audio fra default mic via AVAudioRecorder.
///
/// Skiftet fra AVAudioEngine i M0.E — AVAudioEngine + Bluetooth mic (AirPods)
/// gav konsistent 0 samples på trods af korrekt input-format. AVAudioRecorder
/// er højere-niveau og virker pålideligt på alle input-devices (Built-in,
/// Bluetooth, USB).
///
/// Recorder skriver til en temp .caf-fil ved 16 kHz mono PCM. Ved stop()
/// læses filen ind via soundfile-lignende decode og returneres som
/// `CapturedAudio` (samme interface som før).
@MainActor
public final class AudioCapture {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "audio")

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private let outputSampleRate: Int = 16_000

    public init() {}

    public func start() {
        if recorder?.isRecording == true {
            log.warning("start() kaldt mens recording allerede kører — ignorer")
            return
        }

        let url = makeTempURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else {
                log.error("AVAudioRecorder.prepareToRecord returnerede false")
                return
            }
            guard rec.record() else {
                log.error("AVAudioRecorder.record returnerede false")
                return
            }
            self.recorder = rec
            self.tempURL = url
            log.info("Recorder startet → \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("AVAudioRecorder.init fejlede: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    public func stop() -> CapturedAudio {
        guard let rec = recorder, let url = tempURL else {
            return CapturedAudio(samples: [], sampleRate: outputSampleRate)
        }
        rec.stop()
        let dur = rec.currentTime
        recorder = nil
        tempURL = nil
        log.info("Recorder stoppet — \(dur, privacy: .public) sek (rec.currentTime)")

        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let samples = try readWavSamples(at: url, sampleRate: self.outputSampleRate)
            let secs = Double(samples.count) / Double(self.outputSampleRate)
            log.info("Læste \(samples.count, privacy: .public) samples (\(secs, privacy: .public) sek)")
            return CapturedAudio(samples: samples, sampleRate: self.outputSampleRate)
        } catch {
            log.error("Kunne ikke læse audio-fil: \(error.localizedDescription, privacy: .public)")
            return CapturedAudio(samples: [], sampleRate: outputSampleRate)
        }
    }

    private func makeTempURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("saga-rec-\(UUID().uuidString).wav")
        return tmp
    }

    /// Læs en 16-bit PCM WAV-fil og konverter til float32 [-1, 1].
    /// Antager mono og target sample-rate (filen er allerede skrevet i det format).
    private func readWavSamples(at url: URL, sampleRate: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Saga", code: 1, userInfo: [NSLocalizedDescriptionKey: "PCMBuffer-allokering fejlede"])
        }
        try file.read(into: buffer)

        let actualFrames = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "Saga", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio-fil har ikke float channel-data"])
        }

        let mono = UnsafeBufferPointer(start: channelData[0], count: actualFrames)
        var samples = Array(mono)

        // AVAudioFile.processingFormat kan have anden sample-rate end target.
        // Hvis ikke 16 kHz, lav simpel linear resample (kvalitet er nok for ASR).
        if Int(format.sampleRate) != sampleRate {
            let inputSr = Int(format.sampleRate)
            let ratio = Double(sampleRate) / Double(inputSr)
            let outLen = Int(Double(samples.count) * ratio)
            var out = [Float](repeating: 0, count: outLen)
            for i in 0..<outLen {
                let srcIdx = Double(i) / ratio
                let lo = Int(srcIdx.rounded(.down))
                let hi = min(lo + 1, samples.count - 1)
                let frac = Float(srcIdx - Double(lo))
                out[i] = samples[lo] * (1 - frac) + samples[hi] * frac
            }
            samples = out
        }

        return samples
    }
}

public struct CapturedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int

    public var duration: Double { Double(samples.count) / Double(sampleRate) }

    /// Pak til lille-endian 16-bit PCM bytes.
    public var pcm16Data: Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16(clamped * 32767.0)
            withUnsafeBytes(of: scaled.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
