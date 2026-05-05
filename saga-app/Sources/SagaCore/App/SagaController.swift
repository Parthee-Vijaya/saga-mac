import AppKit
import AVFoundation
import Combine
import Foundation
import OSLog

/// Top-level orkestrator. Holder alle moduler og koordinerer hotkey → audio → transcribe → inject.
///
/// ASR-backend er CanaryKit (NVIDIA Canary-1b-v2 → CoreML, Apple Silicon native).
/// Hviske var ASR i M0–M0.C men producerede multilingual junk på MPS — pivoteret til
/// canary-coreml efter user's tidligere arbejde på det projekt. Hviske-coreml planlægges
/// som drop-in-erstatning når den er konverteret (~10 dages sideprojekt).
@MainActor
public final class SagaController: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "controller")

    public let hud: RecordingHUDController
    public let hotkeys: HotkeyManager
    public let audio: AudioCapture
    public let cursor: CursorInjector
    public let asr: CanaryASRBridge
    public let lmStudio: LMStudioBridge
    public let modes: ModeRouter
    public let health: HealthMonitor
    public let history: HistoryStore
    public let reminders: ReminderEngine
    public let vision: ScreenVision
    public let documents: DocumentAnalyzer
    public let wakeWord: WakeWordDetector
    public let tts: TTSCoordinator
    public let companion: CompanionController

    @Published public private(set) var state: SagaState = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var booted = false
    @Published public private(set) var discoveredEndpoints: [DiscoveredEndpoint] = []
    @Published public private(set) var isDiscoveringLMStudio = false
    @Published public var showFirstRun: Bool = false

    /// Stenograf-mode: ren dictation. Springer mode-routing, LM Studio,
    /// reminders, vision og document-analysis over. Kun Canary → cursor.
    /// Bruges når brugeren vil have minimal forsinkelse og ingen LLM-afhængighed.
    @Published public var stenografMode: Bool {
        didSet {
            UserDefaults.standard.set(stenografMode, forKey: "stenografMode")
            log.info("Stenograf-mode: \(self.stenografMode ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Wake-word-mode: continuous listening efter "Hej Saga". Default OFF
    /// (mere indgribende end push-to-talk). Toggle via Settings → Wake-word.
    @Published public var wakeWordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wakeWordEnabled, forKey: "wakeWordEnabled")
            log.info("Wake-word: \(self.wakeWordEnabled ? "TIL" : "FRA", privacy: .public)")
            applyWakeWordState()
        }
    }

    /// Maks varighed af wake-word-trigget recording (sek). Efter triggering
    /// optager vi i denne periode og auto-stopper.
    @Published public var wakeWordRecordingDuration: TimeInterval = 6.0

    public init() {
        self.hud = RecordingHUDController()
        self.hotkeys = HotkeyManager()
        self.audio = AudioCapture()
        self.cursor = CursorInjector()
        self.asr = CanaryASRBridge()
        self.lmStudio = LMStudioBridge()
        self.modes = ModeRouter()
        self.health = HealthMonitor()
        self.history = HistoryStore()
        self.reminders = ReminderEngine()
        self.vision = ScreenVision()
        self.documents = DocumentAnalyzer()
        self.wakeWord = WakeWordDetector()
        self.tts = TTSCoordinator()
        self.companion = CompanionController()
        self.stenografMode = UserDefaults.standard.bool(forKey: "stenografMode")
        self.wakeWordEnabled = UserDefaults.standard.bool(forKey: "wakeWordEnabled")
    }

    public var menuBarIconName: String {
        switch state {
        case .idle: return health.asr.isHappy ? "waveform.circle" : "waveform.circle.fill"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .routing: return "sparkles"
        }
    }

    public func bootIfNeeded() async {
        guard !booted else { return }
        booted = true
        log.info("Saga booter")

        hud.attach(controller: self)
        health.attach(asr: asr)
        health.start()

        requestMicrophonePermissionIfNeeded()

        // Start CoreML-load i baggrunden. FP16 indtil int4-kvantisering er færdig.
        Task { [asr] in
            await asr.load(useInt4: false)
        }

        // Aktivér hotkey-listening
        hotkeys.onHoldStart = { [weak self] in self?.handleHoldStart() }
        hotkeys.onHoldEnd = { [weak self] in self?.handleHoldEnd() }
        hotkeys.startListening()

        // Wire Companion til denne controller — den deler audio, asr, lmStudio, tts, vision.
        companion.attach(saga: self)

        // Wire wake-word callback med routing-branch:
        // - Hvis Companion er aktiveret i Settings → start voice-conversation
        // - Ellers → eksisterende dictation-flow (kort timeout, type-at-cursor)
        wakeWord.onWake = { [weak self] in
            guard let self else { return }
            if self.companion.enabled {
                self.companion.startSession()
            } else {
                self.handleWakeWordTrigger()
            }
        }
        applyWakeWordState()

        // Auto-detect LM Studio på baggrunden — ikke-blocking
        Task { [weak self] in
            await self?.discoverLMStudio(autoConfigure: true)
        }
    }

    private func applyWakeWordState() {
        guard booted else { return }
        if wakeWordEnabled {
            Task { @MainActor in
                let auth = await WakeWordDetector.requestAuthorization()
                if auth == .authorized {
                    wakeWord.start()
                } else {
                    lastError = "Speech recognition-permission mangler. Slå Wake-word fra eller granté i System Settings."
                    self.wakeWordEnabled = false
                }
            }
        } else {
            wakeWord.stop()
        }
    }

    private func handleWakeWordTrigger() {
        // Wake-word fyrede — start optagelse som hvis brugeren havde holdt Fn,
        // og auto-stop efter wakeWordRecordingDuration (eller hvis bruger holder
        // Fn imens, lader vi den manuelle hold tage over).
        guard state == .idle else { return }
        log.info("Wake-word triggered → start recording")
        handleHoldStart()
        let duration = wakeWordRecordingDuration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // Hvis vi stadig er i recording-state efter timeout: stop
            if state == .recording {
                handleHoldEnd()
            }
        }
    }

    /// Scan localhost for LM Studio (eller anden OpenAI-kompatibel server).
    /// `autoConfigure: true` opdaterer brugerens config hvis (a) der er ingen
    /// config gemt eller (b) den gemte URL ikke svarer.
    public func discoverLMStudio(autoConfigure: Bool = false) async {
        isDiscoveringLMStudio = true
        defer { isDiscoveringLMStudio = false }

        let endpoints = await lmStudio.discover()
        self.discoveredEndpoints = endpoints
        log.info("LM Studio discovery: fandt \(endpoints.count, privacy: .public) endpoints")

        guard autoConfigure, let first = endpoints.first else { return }

        let savedURL = UserDefaults.standard.string(forKey: "lmStudioBaseURL") ?? ""
        let savedConfigured = !savedURL.isEmpty && savedURL != "http://localhost:1234/v1"

        // Auto-configure hvis bruger ikke har sat noget custom OG den gemte
        // default ikke svarer (LM Studio kører måske på anden port end 1234).
        if !savedConfigured {
            UserDefaults.standard.set(first.baseURL.absoluteString, forKey: "lmStudioBaseURL")
            if let firstModel = first.models.first {
                UserDefaults.standard.set(firstModel, forKey: "lmStudioModel")
            }
            log.info("Auto-configured LM Studio: \(first.baseURL.absoluteString, privacy: .public)")
            lmStudio.configure(baseURL: first.baseURL, model: first.models.first ?? "")
        }
    }

    public func shutdown() async {
        log.info("Saga lukker ned")
        hotkeys.stopListening()
        wakeWord.stop()
        audio.stop()
        health.stop()
    }

    public func requestFirstRun() {
        showFirstRun = true
    }

    public func dismissFirstRun() {
        showFirstRun = false
    }

    public func reloadASR() {
        Task { [asr] in
            await asr.load(useInt4: false)
        }
    }

    public func requestMicrophonePermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .notDetermined:
            log.info("Beder om mikrofon-permission")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.log.info("Mikrofon-permission granted: \(granted)")
                    if !granted {
                        self?.lastError = "Mikrofon-adgang blev nægtet. Aktivér i System Settings → Privacy → Microphone."
                    }
                }
            }
        case .denied, .restricted:
            log.warning("Mikrofon-permission er nægtet")
            lastError = "Mikrofon-adgang mangler. Aktivér i System Settings → Privacy → Microphone."
        case .authorized:
            log.info("Mikrofon-permission OK")
        @unknown default:
            break
        }
    }

    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recording lifecycle

    private func handleHoldStart() {
        guard state == .idle else { return }
        guard asr.isReady else {
            log.warning("ASR ikke klar — ignorer hotkey")
            lastError = "ASR-modellen er stadig ved at indlæse. Vent på \"Klar\"-status."
            return
        }
        // Pause wake-word så det ikke konkurrerer om mic-input
        wakeWord.pauseForRecording()
        lastError = nil
        state = .recording
        hud.show()
        audio.start()
    }

    private func handleHoldEnd() {
        guard state == .recording else { return }
        state = .transcribing
        hud.update(state: .transcribing)

        let pcm = audio.stop()
        guard pcm.duration > 0.3 else {
            log.info("Optagelse for kort (\(pcm.duration)s) — ignorer")
            state = .idle
            hud.dismiss()
            return
        }

        Task { @MainActor in
            do {
                let transcript = try await asr.transcribe(pcm: pcm, language: "da")

                if stenografMode {
                    // Stenograf-mode: skip alt mode-routing, gå direkte til cursor.
                    cursor.type(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    history.append(TranscriptEntry(
                        rawText: transcript.text,
                        processedText: transcript.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        modeId: nil,
                        durationMs: transcript.durationMs,
                        inferenceMs: transcript.inferenceMs
                    ))
                    state = .idle
                    hud.dismiss()
                    wakeWord.resumeAfterRecording()
                    return
                }

                state = .routing
                hud.update(state: .routing)

                let result: RouteResult
                do {
                    if let preview = modes.previewMatch(for: transcript.text) {
                        hud.update(state: .routing, activeMode: preview)
                    }
                    result = try await modes.route(text: transcript.text, controller: self)
                } catch let modeError as ModeError {
                    log.warning("Mode-routing fejlede, falder tilbage til rå-transkription")
                    lastError = modeError.errorDescription
                    result = RouteResult(text: modeError.fallbackText ?? transcript.text, mode: nil)
                }

                cursor.type(result.text)

                history.append(TranscriptEntry(
                    rawText: transcript.text,
                    processedText: result.text,
                    modeId: result.mode?.id,
                    durationMs: transcript.durationMs,
                    inferenceMs: transcript.inferenceMs
                ))

                state = .idle
                hud.dismiss()
                wakeWord.resumeAfterRecording()
            } catch {
                log.error("Pipeline fejlede: \(error.localizedDescription)")
                lastError = error.localizedDescription
                state = .idle
                hud.show(error: error)
                wakeWord.resumeAfterRecording()
            }
        }
    }
}

public enum SagaState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case routing
}

public struct TranscribeResult: Sendable {
    public let text: String
    public let durationMs: Int
    public let inferenceMs: Int
    public let rtf: Double

    public init(text: String, durationMs: Int, inferenceMs: Int, rtf: Double) {
        self.text = text
        self.durationMs = durationMs
        self.inferenceMs = inferenceMs
        self.rtf = rtf
    }
}
