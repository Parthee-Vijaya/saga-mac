@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// Continuous on-device wake-word-detection. Bruger SFSpeechRecognizer med
/// `requiresOnDeviceRecognition = true` (macOS 13+) så ingen audio sendes til
/// Apple's cloud. Når detector matcher en wake-frase, kalder den `onWake`-closure
/// — typisk binder SagaController det til at starte recording.
///
/// **Default OFF.** Bruger opt-in via Settings (kræver speech recognition-permission
/// + altid-on mikrofon, hvilket er mere indgribende end push-to-talk).
@MainActor
public final class WakeWordDetector: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "wake-word")

    /// Frasen(er) Saga lytter efter. Hver match-test er case-insensitive substring.
    /// Default: bare "saga" (kort + naturligt). "hej saga"/"hey saga" matches også
    /// pga. substring-test. Risiko for false positives hvis bruger taler om "saga"
    /// i andre sammenhænge — overvej at vælge mere distinkt frase i Settings senere.
    public var phrases: [String] = ["saga"]

    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastDetection: Date?

    /// Kaldes når en wake-frase detected. Detector pauser sig selv før callback,
    /// så loop ikke kommer ud af kontrol — caller skal kalde resume() når klar.
    public var onWake: (() -> Void)?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var pausedForRecording: Bool = false

    public init(locale: Locale = Locale(identifier: "da-DK")) {
        // Falder tilbage til en-US hvis dansk recognizer ikke er tilgængelig
        if let danish = SFSpeechRecognizer(locale: locale) {
            self.speechRecognizer = danish
        } else {
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    /// `nonisolated` — uden dette arves @MainActor fra class og Swift-runtime
    /// crasher når TCC's callback (på TCC-queue) prøver at resume continuation
    /// gennem isolated executor-check (`swift_task_isCurrentExecutorWithFlagsImpl`).
    /// Continuation-mekanik håndterer selv thread-hop tilbage til caller.
    public nonisolated static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    public nonisolated func currentAuthorization() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    public func start() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            lastError = "Speech recognizer er ikke tilgængelig"
            log.error("Recognizer ikke tilgængelig")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .search  // korte fraser

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            lastError = "Ingen mikrofon tilgængelig"
            return
        }

        inputNode.removeTap(onBus: 0)
        // installTap-callback fyrer på AVAudioEngine's audio render thread, ikke
        // MainActor. Uden @Sendable arver closure'en @MainActor fra class og
        // Swift-runtime crasher i swift_task_isCurrentExecutorWithFlagsImpl.
        // SFSpeechAudioBufferRecognitionRequest.append er thread-safe per Apple's
        // docs, så det er sikkert at kalde fra audio thread.
        nonisolated(unsafe) let weakRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak weakRequest] buffer, _ in
            weakRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            lastError = "Audio-engine fejl: \(error.localizedDescription)"
            log.error("Audio-engine: \(error.localizedDescription, privacy: .public)")
            return
        }

        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleResult(result: result, error: error)
            }
        }

        isListening = true
        lastError = nil
        log.info("Wake-word listener startet (locale=\(recognizer.locale.identifier, privacy: .public))")
    }

    public func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    /// Pauser detector mens hovedrecording kører — undgår at wake-word
    /// detector tilføjer audio til samme inputNode som AudioCapture.
    public func pauseForRecording() {
        guard isListening else { return }
        pausedForRecording = true
        stop()
    }

    /// Genoptager efter recording-flow er færdigt.
    public func resumeAfterRecording() {
        guard pausedForRecording else { return }
        pausedForRecording = false
        start()
    }

    private func handleResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error as NSError? {
            log.warning("Recognition fejl: \(error.localizedDescription, privacy: .public)")
            stop()

            let msg = error.localizedDescription.lowercased()
            // Fundamentale fejl — auto-disable + vis klar besked. Ingen retry-loop.
            if msg.contains("siri and dictation are disabled") || msg.contains("siri or dictation") {
                lastError = "Wake-word kræver at Siri eller Dictation er enabled i System Settings → Apple Intelligence & Siri (eller Keyboard → Dictation)."
                log.error("Wake-word disabled: bruger skal enable Dictation/Siri")
                return
            }
            if msg.contains("not authorized") || msg.contains("not permitted") {
                lastError = "Speech recognition-permission er trukket tilbage. Granté igen i Settings."
                return
            }
            // Cancelled — bare stop, ingen retry
            if error.code == 203 || error.code == 1 {
                return
            }
            // Andre fejl — én restart-forsøg efter 2 sek
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !pausedForRecording && !isListening {
                    self.start()
                }
            }
            return
        }

        guard let result else { return }
        let transcript = result.bestTranscription.formattedString.lowercased()
        guard !transcript.isEmpty else { return }

        // Match wake-fraser
        for phrase in phrases {
            if transcript.contains(phrase.lowercased()) {
                log.info("Wake-word matched: '\(phrase, privacy: .public)' i '\(transcript, privacy: .public)'")
                lastDetection = Date()
                pauseForRecording()  // stop os selv så vi ikke loop'er
                onWake?()
                return
            }
        }

        // Hvis recognizer rapporterer "final result" uden match, restart for at
        // få en frisk session (recognizers timer typisk ud efter ~1 minut)
        if result.isFinal {
            stop()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if !pausedForRecording { self.start() }
            }
        }
    }
}
