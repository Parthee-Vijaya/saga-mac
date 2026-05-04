@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Capture mono float32 audio fra default mic, resample til 16 kHz, returnér som PCM-buffer.
///
/// AVAudioEngine kalder vores tap-callback på en intern audio-tråd. Vi laver al konvertering
/// dér og pusher samples ind i en lås-beskyttet bucket. ``stop()`` henter bucket'en på MainActor.
@MainActor
public final class AudioCapture {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "audio")

    private let engine = AVAudioEngine()
    private let bucket = SampleBucket()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outputFormat: AVAudioFormat
    private var isRunning = false

    public init() {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    public func start() {
        guard !isRunning else { return }
        bucket.reset()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        inputFormat = format

        log.debug("Input format: sr=\(format.sampleRate) ch=\(format.channelCount)")

        if format.sampleRate != outputFormat.sampleRate || format.channelCount != outputFormat.channelCount {
            converter = AVAudioConverter(from: format, to: outputFormat)
        } else {
            converter = nil
        }

        let bucket = self.bucket
        let converter = self.converter
        let outputFormat = self.outputFormat

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            Self.process(
                buffer: buffer,
                converter: converter,
                outputFormat: outputFormat,
                bucket: bucket
            )
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            log.info("Audio-engine startet")
        } catch {
            log.error("Engine.start fejlede: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func stop() -> CapturedAudio {
        guard isRunning else {
            return CapturedAudio(samples: [], sampleRate: Int(outputFormat.sampleRate))
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        let samples = bucket.drain()
        log.info("Audio-engine stoppet — \(samples.count) samples (\(Double(samples.count) / 16_000.0) sek)")
        return CapturedAudio(samples: samples, sampleRate: Int(outputFormat.sampleRate))
    }

    nonisolated private static func process(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat,
        bucket: SampleBucket
    ) {
        let resampled: AVAudioPCMBuffer
        if let converter, let inputFormat = converter.inputFormat as AVAudioFormat? {
            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
            guard let outBuf = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outCapacity
            ) else { return }

            let feeder = BufferFeeder(buffer: buffer)
            var error: NSError?
            converter.convert(to: outBuf, error: &error) { _, statusPtr in
                feeder.next(statusPtr)
            }
            if error != nil {
                return
            }
            resampled = outBuf
        } else {
            resampled = buffer
        }

        guard let channelData = resampled.floatChannelData else { return }
        let frames = Int(resampled.frameLength)
        let mono = UnsafeBufferPointer(start: channelData[0], count: frames)
        bucket.append(Array(mono))
    }
}

/// Tråd-sikker samples-bucket. ``append`` kaldes fra audio-thread, ``drain`` fra MainActor.
final class SampleBucket: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    func append(_ chunk: [Float]) {
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let out = samples
        samples = []
        lock.unlock()
        return out
    }

    func reset() {
        lock.lock()
        samples = []
        lock.unlock()
    }
}

/// AVAudioConverter callback-feeder der kun returnerer buffer'en én gang.
final class BufferFeeder: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var fed = false
    private let lock = NSLock()

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ statusPtr: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if fed {
            statusPtr.pointee = .noDataNow
            return nil
        }
        fed = true
        statusPtr.pointee = .haveData
        return buffer
    }
}

public struct CapturedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int

    public var duration: Double { Double(samples.count) / Double(sampleRate) }

    /// Pak til lille-endian 16-bit PCM bytes. Hviske-sidecar dekoder dette via "pcm16"-encoding.
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
