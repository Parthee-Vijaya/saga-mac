@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// On-device live partial-transcript via SFSpeechRecognizer.
///
/// Saga's authoritative transcription er Canary (bedre dansk-kvalitet), men
/// Canary er non-streaming — den kører først når recordingen er færdig. For
/// at give brugeren live-feedback under taleturen i Companion-mode bruger vi
/// Apple's on-device recognizer parallel med AudioCapture, og overskriver så
/// med Canary's authoritative resultat ved turn-end.
///
/// Audio kommer fra AVAudioEngine — separat fra AudioCapture's AVAudioRecorder.
/// Begge subsystems læser fra samme mikrofon men igennem forskellige routes,
/// så ingen konflikt i praksis.
@MainActor
public final class LivePartialTranscriber {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "live-partial")

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var onPartial: (@MainActor (String) -> Void)?
    private(set) var isRunning: Bool = false

    public init(locale: Locale = Locale(identifier: "da-DK")) {
        if let danish = SFSpeechRecognizer(locale: locale) {
            self.speechRecognizer = danish
        } else {
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    /// Start live recognition. Callback fyrer hver gang partial-result opdateres.
    /// Idempotent — gentagne start() før stop() er no-op.
    public func start(onPartial: @escaping @MainActor (String) -> Void) {
        guard !isRunning else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            log.warning("LivePartialTranscriber: recognizer ikke tilgængelig")
            return
        }
        self.onPartial = onPartial

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            log.warning("LivePartialTranscriber: ingen mikrofon")
            return
        }

        inputNode.removeTap(onBus: 0)
        // installTap-callback fyrer på AVAudioEngine's audio render thread,
        // ikke MainActor. Uden @Sendable arver closure'en @MainActor fra class
        // og Swift-runtime crasher i swift_task_isCurrentExecutorWithFlagsImpl.
        // Samme fix-pattern som WakeWordDetector.
        nonisolated(unsafe) let weakRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak weakRequest] buffer, _ in
            weakRequest?.append(buffer)
        }

        recognitionRequest = request
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            log.warning("LivePartialTranscriber: AVAudioEngine.start fejlede: \(error.localizedDescription, privacy: .public)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    if !transcript.isEmpty {
                        self.onPartial?(transcript)
                    }
                }
                if error != nil || result?.isFinal == true {
                    self.cleanupAfterTaskEnds()
                }
            }
        }

        isRunning = true
        log.info("LivePartialTranscriber startet")
    }

    /// Stop recognition og frigør mic-tap. Idempotent.
    public func stop() {
        guard isRunning else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        isRunning = false
        onPartial = nil
        log.info("LivePartialTranscriber stoppet")
    }

    private func cleanupAfterTaskEnds() {
        // Kaldes fra recognition-callback når SFSpeechRecognizer afslutter
        // (final eller fejl). Ryd op uden at fyre onPartial igen.
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isRunning = false
    }
}
