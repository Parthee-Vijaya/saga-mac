import Foundation
import OSLog

/// State machine for én Companion-samtale fra wake-word til "tak".
///
/// Kører parallelt med SagaController's dictation-flow — Companion er IKKE
/// hooked ind i ModeRouter. Når aktiv, holder den microphone-input til sig
/// selv via wakeWord.pauseForRecording() så dictation-hotkey ikke konkurrerer.
@MainActor
public final class CompanionController: ObservableObject {
    private let log = Logger(subsystem: "dk.parthee.saga", category: "companion")

    public let session: CompanionSession
    public let overlay: CompanionOverlayController
    public let cursorBubble: CursorBubbleController
    private weak var saga: SagaController?

    @Published public private(set) var state: CompanionState = .idle {
        didSet {
            // Vis overlay + bubble ved aktiv samtale, dismiss når vi går idle.
            if state == .idle, oldValue != .idle {
                overlay.dismiss()
                cursorBubble.dismiss()
            } else if state != .idle, oldValue == .idle {
                overlay.show()
                cursorBubble.show()
            }
        }
    }
    @Published public private(set) var lastError: String?

    /// Live transcript af brugerens igangværende tur (vises i overlay/HUD i Sprint C3).
    @Published public private(set) var currentUserPartial: String = ""

    /// Senest færdige assistant-respons (akkumulerer som tokens streames ind).
    @Published public private(set) var currentAssistantBuffer: String = ""

    /// Master enable — sættes via Settings. Når false ignoreres companion-phrases helt.
    @Published public var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "companion.enabled")
        }
    }

    /// Hvor lang stilhed der skal til før vi auto-stopper en tur. 0.8s er
    /// kompromis mellem snappy turn-taking og ikke-afbrudt-tænkning.
    public var turnSilenceDuration: TimeInterval = 0.8

    /// Min varighed før silence-detection må kicke ind. Forhindrer at en 0.1s
    /// recording afsluttes før brugeren har nået at sige noget.
    public var minTurnDuration: TimeInterval = 0.5

    /// Energy-tærskel for silence (samme normaliserede skala som AudioCapture).
    public var silenceThreshold: Float = 0.05

    private var currentTurnTask: Task<Void, Never>?
    private var silenceMonitorTask: Task<Void, Never>?
    private var turnStartedAt: Date?
    private var silenceStartedAt: Date?
    private var hasHeardSpeech: Bool = false

    public init(
        session: CompanionSession = CompanionSession(),
        overlay: CompanionOverlayController = CompanionOverlayController(),
        cursorBubble: CursorBubbleController = CursorBubbleController()
    ) {
        self.session = session
        self.overlay = overlay
        self.cursorBubble = cursorBubble
        self.enabled = UserDefaults.standard.bool(forKey: "companion.enabled")
    }

    /// Wire-up — kaldes fra SagaController.bootIfNeeded.
    public func attach(saga: SagaController) {
        self.saga = saga
        overlay.attach(companion: self, audio: saga.audio)
        cursorBubble.attach(companion: self)
    }

    // MARK: - Public API

    /// Start en ny session (eller fortsæt eksisterende). Kaldes typisk fra
    /// wake-word-callback eller en Settings-test-knap.
    public func startSession() {
        guard enabled else {
            log.info("startSession ignoreret — Companion disabled")
            return
        }
        guard state == .idle else {
            log.info("startSession ignoreret — state=\(String(describing: self.state), privacy: .public)")
            return
        }
        guard saga?.asr.isReady == true else {
            lastError = "ASR-modellen er ikke klar endnu."
            return
        }
        log.info("Companion: startSession")
        session.reset()
        currentAssistantBuffer = ""
        currentUserPartial = ""
        lastError = nil
        startNextTurn()
    }

    /// Afslut sessionen og frigiv mic + wake-word.
    public func endSession() {
        log.info("Companion: endSession")
        cancelCurrentTurn(reason: "session-end")
        Task { @MainActor in
            saga?.tts.stop()
            saga?.audio.stop()
            saga?.wakeWord.resumeAfterRecording()
        }
        state = .idle
        currentUserPartial = ""
    }

    /// Cancel den igangværende tur uden at afslutte session — nyttigt hvis
    /// brugeren vil afbryde Saga's igangværende svar og selv tale.
    public func cancelCurrentTurn(reason: String) {
        log.info("Companion: cancelCurrentTurn — \(reason, privacy: .public)")
        currentTurnTask?.cancel()
        currentTurnTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        saga?.tts.stop()
    }

    // MARK: - Turn lifecycle

    private func startNextTurn() {
        guard let saga else { return }
        state = .listening
        currentUserPartial = ""
        turnStartedAt = Date()
        silenceStartedAt = nil
        hasHeardSpeech = false

        saga.wakeWord.pauseForRecording()
        saga.audio.start()

        // Start silence-monitor parallelt
        silenceMonitorTask?.cancel()
        silenceMonitorTask = Task { @MainActor [weak self] in
            await self?.monitorSilenceUntilTurnEnds()
        }
    }

    /// Polling-baseret silence detection direkte mod AudioCapture.levelHistory.
    /// Inline (uden at kræve VADDetector fra Sprint B) — kan refactores når
    /// Sprint B's EnergyVAD merges til main.
    private func monitorSilenceUntilTurnEnds() async {
        guard let saga else { return }
        while !Task.isCancelled, state == .listening {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 20 Hz polling
            guard let started = turnStartedAt else { continue }
            let elapsed = Date().timeIntervalSince(started)

            // Tjek seneste level fra AudioCapture
            let recentLevel = saga.audio.levelHistory.last ?? 0
            if recentLevel >= silenceThreshold {
                hasHeardSpeech = true
                silenceStartedAt = nil
                continue
            }

            guard hasHeardSpeech, elapsed >= minTurnDuration else { continue }

            if silenceStartedAt == nil {
                silenceStartedAt = Date()
            }
            if let silenceStart = silenceStartedAt,
               Date().timeIntervalSince(silenceStart) >= turnSilenceDuration {
                log.info("Companion: silence-trigger efter \(elapsed, privacy: .public)s recording")
                await finishCurrentTurn()
                return
            }
        }
    }

    private func finishCurrentTurn() async {
        guard let saga, state == .listening else { return }
        state = .transcribing
        let pcm = saga.audio.stop()

        guard pcm.duration > 0.3 else {
            log.info("Companion: tur for kort (\(pcm.duration, privacy: .public)s) — afslut session")
            endSession()
            return
        }

        currentTurnTask = Task { @MainActor [weak self] in
            await self?.processTurn(pcm: pcm)
        }
    }

    private func processTurn(pcm: CapturedAudio) async {
        guard let saga else { return }

        // Transkribér
        let transcript: TranscribeResult
        do {
            transcript = try await saga.asr.transcribe(pcm: pcm, language: "da")
        } catch {
            lastError = "Kunne ikke transkribere: \(error.localizedDescription)"
            log.error("Companion ASR-fejl: \(error.localizedDescription, privacy: .public)")
            endSession()
            return
        }

        let userText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else {
            log.info("Companion: tom transcript — luk session")
            endSession()
            return
        }
        currentUserPartial = userText

        // Tjek end-of-session keywords FØR LLM-kald — sparer tokens og latency
        if isEndOfSessionPhrase(userText) {
            log.info("Companion: bruger sagde end-of-session-frase — luk session")
            endSession()
            return
        }

        // Tag screenshot (vision-context)
        let screenshot = await saga.vision.captureFrontmostWindow()
        session.appendUser(userText, screenshot: screenshot)

        // Stream svar fra LM Studio
        state = .thinking
        currentAssistantBuffer = ""
        var flusher = SentenceFlusher()
        var fullReply = ""

        do {
            let stream = saga.lmStudio.chatStream(messages: session.messagesForLLM())
            for try await chunk in stream {
                if Task.isCancelled { break }
                fullReply.append(chunk)
                currentAssistantBuffer = fullReply
                state = .speaking

                let sentences = flusher.append(chunk)
                for sentence in sentences {
                    if Task.isCancelled { break }
                    await saga.tts.speak(sentence)
                }
            }
            // Tail — hvis sidste fragment ikke endte med ./?/!
            if let tail = flusher.flush() {
                await saga.tts.speak(tail)
            }
        } catch {
            lastError = "LM Studio fejlede: \(error.localizedDescription)"
            log.warning("Companion LLM-fejl: \(error.localizedDescription, privacy: .public)")
            // Forsøg fallback-besked via TTS så bruger ikke står i stilhed
            await saga.tts.speak("Beklager, jeg kunne ikke kontakte LM Studio.")
            endSession()
            return
        }

        let trimmedReply = fullReply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReply.isEmpty {
            session.appendAssistant(trimmedReply)
        }

        // Klar til næste tur
        log.info("Companion: tur færdig, klar til næste")
        startNextTurn()
    }

    private func isEndOfSessionPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
        return CompanionSession.endOfSessionPhrases.contains(normalized)
    }
}

public enum CompanionState: String, Sendable, Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
}
