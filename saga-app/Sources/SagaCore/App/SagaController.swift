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
    public let appleSpeech: AppleSpeechBridge
    public let asrRouter: MultilingualASRRouter
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
    public let updates: UpdateManager
    public let modelDownloader: ModelDownloader
    public let appProfiles: AppProfileStore
    public let vocabulary: VocabularyStore
    public let snippets: SnippetStore
    private let vocabularyProcessor = VocabularyPostProcessor()
    private let fillerRemover = FillerWordRemover()
    private let snippetExpander = SnippetExpander()
    private let selectionReader = SelectionReader()

    /// Live partial transcript via Apple's SFSpeechRecognizer parallel med Canary.
    /// Vises i HUD under recording for instant feedback. Erstattes med Canary's
    /// authoritative transcript ved release.
    private let livePartial = LivePartialTranscriber()

    /// Live partial-transkript fra SFSpeechRecognizer mens bruger holder ⌥.
    /// Tom string mellem recordings.
    @Published public private(set) var currentPartial: String = ""

    /// Akkumulerede statistikker (totale ord/tegn/lyd-minutter).
    /// Vises i Settings → Om → Statistik.
    public let stats = TranscriptionStatsStore()

    /// Daglig voice-journal — alle dictations samles i markdown-filer.
    /// Default disabled, brugeren opt-in via Settings.
    public let journal = JournalStore()

    /// Toggle for daily journal. Når aktiv: hver succesfuld transcribe
    /// appendes til ~/Saga-journal/YYYY-MM-DD.md med timestamp-header.
    @Published public var journalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(journalEnabled, forKey: "journalEnabled")
            log.info("Daily journal: \(self.journalEnabled ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Privacy-mode: når aktiv suspenderes al history-logging (HistoryStore +
    /// TranscriptionStats + JournalStore). Brugbart når du dikterer fortrolige
    /// data (adgangskoder, kreditkort osv.). HUD viser shield-badge i stedet
    /// for engine-badge så brugeren ser at det er aktivt. IKKE persisteret —
    /// nulstilles ved hver app-start.
    @Published public var privacyMode: Bool = false {
        didSet {
            log.info("Privacy mode: \(self.privacyMode ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Toggle privacy-mode. Kaldes fra menubar-shortcut og Settings.
    public func togglePrivacyMode() {
        privacyMode.toggle()
    }

    /// Wrapper omkring history.append der skipper hvis privacy-mode er aktiv.
    /// Bruges fra alle 4 success-paths i handleHoldEnd.
    private func recordHistoryEntryIfAllowed(_ entry: TranscriptEntry) {
        guard !privacyMode else { return }
        history.append(entry)
    }

    /// Seneste transkriberings-latens i millisekunder. Vises i HUD ved siden
    /// af timeren. Reset ved næste recording-start.
    @Published public private(set) var lastTranscribeMs: Int? = nil

    /// Navnet på engine-en der lavede den seneste transkription ("Canary",
    /// "Apple Speech", "LM Studio"). Vises i HUD-bottom-bar.
    @Published public private(set) var lastEngineLabel: String? = nil

    /// Sat ved hold-start hvis brugeren holdt Shift+hotkey OG har markeret tekst.
    /// Når != nil ved hold-end: kør EditMode.run direkte i stedet for mode-routing.
    /// Nulstilles efter hver recording (success OR error path).
    private var pendingEditSelection: String?

    /// PID på den app der var frontmost ved edit-mode start. Bruges til at
    /// re-aktivere appen FØR paste'en — så indsætning lander det rigtige sted
    /// selv hvis brugeren klikkede væk mens LM Studio tænkte.
    private var pendingEditTargetPID: pid_t?

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

    /// VAD auto-stop: hvis aktiv, stopper recording automatisk efter
    /// `vadSilenceDuration` sekunders stilhed (efter mindst 0.5s tale).
    /// Default OFF for at bevare den eksisterende push-to-talk-følelse.
    @Published public var vadAutoStopEnabled: Bool {
        didSet {
            UserDefaults.standard.set(vadAutoStopEnabled, forKey: "vadAutoStopEnabled")
            log.info("VAD auto-stop: \(self.vadAutoStopEnabled ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Hvor lang stilhed der skal til før VAD trigger auto-stop. Default 1.2s.
    @Published public var vadSilenceDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(vadSilenceDuration, forKey: "vadSilenceDuration")
        }
    }

    /// Strip pauseord ("øh", "altså", "ligesom") fra Canary-output.
    /// Wispr-Flow-inspireret: gør dictation pænere out-of-the-box. Default ON.
    /// Kører lokalt via regex (ingen LLM nødvendig).
    @Published public var stripFillerWords: Bool {
        didSet {
            UserDefaults.standard.set(stripFillerWords, forKey: "stripFillerWords")
            log.info("Strip filler-words: \(self.stripFillerWords ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Inline AI-kommandoer: hvis bruger siger fx "...skriv det som email"
    /// til sidst i dictation, splitter Saga content fra instruktion og kører
    /// LM Studio. Kræver LM Studio konfigureret. Default ON.
    /// Hvis LM Studio er nede: trigger ignoreres, rå dictation indsættes.
    @Published public var inlineEditEnabled: Bool {
        didSet {
            UserDefaults.standard.set(inlineEditEnabled, forKey: "inlineEditEnabled")
            log.info("Inline AI-kommandoer: \(self.inlineEditEnabled ? "TIL" : "FRA", privacy: .public)")
        }
    }

    /// Aktivt sprog for transkription. Saga vælger ASR-backend (Canary eller
    /// Apple Speech) baseret på dette. Kan overstyres pr. app via AppProfile.
    @Published public var activeLanguage: SagaLanguage {
        didSet {
            UserDefaults.standard.set(activeLanguage.rawValue, forKey: "activeLanguage")
            log.info("Aktivt sprog: \(self.activeLanguage.displayName, privacy: .public) (\(self.activeLanguage.usesCanary ? "Canary" : "Apple", privacy: .public))")
        }
    }

    public init() {
        self.hud = RecordingHUDController()
        self.hotkeys = HotkeyManager()
        self.audio = AudioCapture()
        self.cursor = CursorInjector()
        self.asr = CanaryASRBridge()
        self.appleSpeech = AppleSpeechBridge()
        self.asrRouter = MultilingualASRRouter(canary: self.asr, apple: self.appleSpeech)
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
        self.updates = UpdateManager()
        self.modelDownloader = ModelDownloader()
        self.appProfiles = AppProfileStore()
        self.vocabulary = VocabularyStore()
        self.snippets = SnippetStore()
        self.stenografMode = UserDefaults.standard.bool(forKey: "stenografMode")
        self.wakeWordEnabled = UserDefaults.standard.bool(forKey: "wakeWordEnabled")
        self.vadAutoStopEnabled = UserDefaults.standard.bool(forKey: "vadAutoStopEnabled")
        let savedDuration = UserDefaults.standard.double(forKey: "vadSilenceDuration")
        self.vadSilenceDuration = savedDuration > 0 ? savedDuration : 1.2
        // Filler-strip default ON — overskrives kun hvis bruger eksplicit har slået fra.
        // UserDefaults.bool returnerer false for ikke-eksisterende key, så vi
        // bruger object(forKey:) for at tjekke om bruger har sat eksplicit.
        if let saved = UserDefaults.standard.object(forKey: "stripFillerWords") as? Bool {
            self.stripFillerWords = saved
        } else {
            self.stripFillerWords = true
        }
        if let saved = UserDefaults.standard.object(forKey: "inlineEditEnabled") as? Bool {
            self.inlineEditEnabled = saved
        } else {
            self.inlineEditEnabled = true
        }
        if let savedLang = UserDefaults.standard.string(forKey: "activeLanguage"),
           let lang = SagaLanguage(rawValue: savedLang) {
            self.activeLanguage = lang
        } else {
            self.activeLanguage = .default
        }
        // Journal default OFF — brugeren skal opt-in. UserDefaults.bool returnerer
        // false for ikke-eksisterende key, hvilket matcher default OFF.
        self.journalEnabled = UserDefaults.standard.bool(forKey: "journalEnabled")
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
        hud.onCancel = { [weak self] in self?.cancelRecording() }
        health.attach(asr: asr)
        health.start()

        requestMicrophonePermissionIfNeeded()

        // Start CoreML-load i baggrunden. FP16 indtil int4-kvantisering er færdig.
        Task { [asr] in
            await asr.load(useInt4: false)
        }

        // Aktivér hotkey-listening
        hotkeys.onHoldStart = { [weak self] shiftHeld in self?.handleHoldStart(forceEdit: shiftHeld) }
        hotkeys.onHoldEnd = { [weak self] in self?.handleHoldEnd() }
        hotkeys.startListening()

        // Wire Companion til denne controller — den deler audio, asr, lmStudio, tts, vision.
        companion.attach(saga: self)

        // Start Sparkle-update-checks (scheduled hver 24t pr. SUScheduledCheckInterval).
        updates.start()

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
        // Vi vælger HVER første model der RENT FAKTISK kan loades — LM Studio's
        // /v1/models lister alle tilgængelige models, ikke kun den loadede.
        // En model der kræver mere RAM end systemet har vil fejle med 400 ved
        // første brug. Vi pinger derfor hver model med et tiny test-call før
        // vi auto-configurerer.
        if !savedConfigured {
            UserDefaults.standard.set(first.baseURL.absoluteString, forKey: "lmStudioBaseURL")

            // Prøv den allerede gemte model først hvis den er på discoverede endpoint
            let savedModel = UserDefaults.standard.string(forKey: "lmStudioModel") ?? ""
            var candidates = first.models
            if !savedModel.isEmpty, let idx = candidates.firstIndex(of: savedModel) {
                candidates.remove(at: idx)
                candidates.insert(savedModel, at: 0)
            }

            var workingModel: String?
            for model in candidates {
                if await lmStudio.canUseModel(baseURL: first.baseURL, model: model) {
                    workingModel = model
                    break
                }
                log.warning("LM Studio model '\(model, privacy: .public)' kan ikke loades — prøver næste")
            }

            if let workingModel {
                UserDefaults.standard.set(workingModel, forKey: "lmStudioModel")
                lmStudio.configure(baseURL: first.baseURL, model: workingModel)
                log.info("Auto-configured LM Studio: \(first.baseURL.absoluteString, privacy: .public) model=\(workingModel, privacy: .public)")
            } else {
                lastError = "LM Studio fundet, men ingen af modellerne kunne loades. Vælg manuelt i Indstillinger → Stemme."
                log.warning("Ingen loadable LM Studio model fundet")
            }
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

    /// Annuller igangværende recording uden at sende til ASR. Kaldes fra
    /// HUD'ens esc-monitor eller programmatisk. Idempotent.
    public func cancelRecording() {
        guard state == .recording else { return }
        log.info("Recording annulleret af bruger (esc)")
        livePartial.stop()
        currentPartial = ""
        _ = audio.stop()
        pendingEditSelection = nil
        pendingEditTargetPID = nil
        state = .idle
        hud.dismiss()
        wakeWord.resumeAfterRecording()
    }

    private func handleHoldStart(forceEdit: Bool = false) {
        guard state == .idle else { return }
        guard asr.isReady else {
            log.warning("ASR ikke klar — ignorer hotkey")
            lastError = "ASR-modellen er stadig ved at indlæse. Vent på \"Klar\"-status."
            return
        }
        // Pause wake-word så det ikke konkurrerer om mic-input
        wakeWord.pauseForRecording()
        lastError = nil

        // Edit-mode: hvis Shift var nede ved hotkey-tryk, snapshot den markerede
        // tekst NU (før recording-flow snupper fokus). Først via AX-API (hurtig,
        // ren). Hvis det fejler — typisk i Electron-apps som Claude/Slack/VSCode
        // som ikke eksponerer kAXSelectedText — falder vi tilbage til Cmd+C-trick.
        pendingEditSelection = nil
        pendingEditTargetPID = nil
        if forceEdit {
            // Husk hvilken app der var frontmost — vi bringer den tilbage før
            // paste'en, så indsætning lander det rigtige sted selv hvis brugeren
            // klikker væk mens LM Studio tænker.
            pendingEditTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

            if let selection = selectionReader.currentSelection() {
                pendingEditSelection = selection
                log.info("Edit-mode aktiv (AX-path) — markeret tekst: \(selection.count) chars, target pid=\(self.pendingEditTargetPID ?? -1)")
            } else if let selection = selectionReader.currentSelectionViaClipboard() {
                pendingEditSelection = selection
                log.info("Edit-mode aktiv (clipboard-path) — markeret tekst: \(selection.count) chars, target pid=\(self.pendingEditTargetPID ?? -1)")
            } else {
                log.info("Edit-mode anmodet men ingen markering — falder til normal dictation")
                lastError = "Markér tekst først. ⇧+⌥ uden markering = normal dictation."
                pendingEditTargetPID = nil
            }
        }

        state = .recording
        hud.show()

        // Konfigurer VAD før start hvis bruger har slået auto-stop til.
        if vadAutoStopEnabled {
            let config = VADConfig(
                silenceThreshold: 0.05,
                silenceDuration: vadSilenceDuration,
                minRecordingDuration: 0.5
            )
            audio.enableVAD(config: config) { [weak self] in
                self?.handleHoldEnd()
            }
        } else {
            audio.disableVAD()
        }

        audio.start()

        // Reset transcribe-stats fra forrige recording — ny recording starter clean.
        lastTranscribeMs = nil
        lastEngineLabel = nil

        // Start live partial-transcribe via Apple's SFSpeechRecognizer parallel
        // med Canary. Vises i HUD så bruger får øjeblikkelig feedback. Erstattes
        // af authoritative transcript ved release. Locale matcher aktivt sprog
        // så live partial er på det rigtige sprog (fx tamilsk hvis valgt).
        currentPartial = ""
        let liveLocale = Locale(identifier: activeLanguage.appleLocale)
        livePartial.setLocale(liveLocale)
        livePartial.start { [weak self] partial in
            guard let self, self.state == .recording else { return }
            self.currentPartial = partial
        }
    }

    private func handleHoldEnd() {
        guard state == .recording else { return }
        state = .transcribing
        hud.update(state: .transcribing)
        livePartial.stop()

        let pcm = audio.stop()
        guard pcm.duration > 0.3 else {
            log.info("Optagelse for kort (\(pcm.duration)s) — ignorer")
            pendingEditSelection = nil
            state = .idle
            hud.dismiss()
            return
        }

        // Snapshot edit-state før Task hopper til background — den nulstilles
        // straks så næste recording starter ren.
        let editSelection = pendingEditSelection
        let editTargetPID = pendingEditTargetPID
        pendingEditSelection = nil
        pendingEditTargetPID = nil

        // Hent per-app profil for frontmost app (snapshot taken før recording stop
        // for at undgå at fokus-skift under recording skifter profil mid-flow).
        let profile = appProfiles.currentProfile()

        // Effektivt sprog: per-app override har højere prioritet end global setting.
        // Brug AppProfile.languageCode hvis sat, ellers global activeLanguage.
        let effectiveLanguage: SagaLanguage = {
            if let profileLang = profile?.languageCode,
               let lang = SagaLanguage(rawValue: profileLang) {
                return lang
            }
            return activeLanguage
        }()

        Task { @MainActor in
            do {
                let transcript = try await asrRouter.transcribe(pcm: pcm, language: effectiveLanguage)

                // Track engine + latency for HUD-display + stats
                lastTranscribeMs = transcript.inferenceMs
                lastEngineLabel = effectiveLanguage.usesCanary ? "Canary" : "Apple Speech"

                // Privacy-mode: skip ALT history-logging når aktivt.
                // Stats, journal og history.append nedenstrøms skal alle
                // respektere flag'et.
                if !privacyMode {
                    stats.record(
                        text: transcript.text,
                        audioSeconds: pcm.duration,
                        inferenceMs: transcript.inferenceMs
                    )
                    if journalEnabled {
                        journal.append(text: transcript.text)
                    }
                } else {
                    log.info("Privacy mode aktivt — skipper stats + journal + history")
                }

                // Vocabulary post-processing — anvend brugerens egennavne/akronymer
                // på den rå transcript før mode-routing. Bevarer den oprindelige
                // tekst i history for transparens.
                let vocabApplied = vocabularyProcessor.apply(
                    transcript.text,
                    entries: vocabulary.activeEntries
                )
                // Filler-word removal — strip "øh", "altså", "ligesom" osv.
                // Kører lokalt (ingen LLM). Toggle i Settings → Generelt.
                let fillerCleaned = stripFillerWords
                    ? fillerRemover.apply(vocabApplied)
                    : vocabApplied
                // Snippet-expansion: trigger-fraser → tekstblokke ("min sig" →
                // signature). Kører efter filler-strip men før mode-routing.
                let correctedText = snippetExpander.apply(
                    fillerCleaned,
                    entries: snippets.activeEntries
                )

                // Forced edit-mode: brugeren holdt Shift+hotkey OG havde markering.
                // Skip ALT mode-routing og send selection+instruktion direkte til LLM.
                if let selection = editSelection {
                    let instruction = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    log.info("Edit-mode kører — selection \(selection.count) chars, instruktion \"\(instruction.prefix(60), privacy: .public)\"")
                    // Skift HUD til "thinking" så brugeren ved Saga arbejder.
                    // EditMode.run kan tage 30-60s på en lokal 26B-model — uden
                    // synlig progress kommer brugeren naturligt til at klikke væk.
                    lastEngineLabel = "LM Studio"
                    state = .routing
                    let editMarker = Mode(id: "edit", title: "Redigerer…", triggers: [], systemPrompt: "")
                    hud.update(state: .routing, activeMode: editMarker)
                    do {
                        let edited = try await EditMode.run(
                            selection: selection,
                            instruction: instruction,
                            controller: self
                        )
                        // Paste i stedet for unicode-keyboard-injection — pålidelig
                        // i Electron-apps der opsluger CGEvent-unicode events.
                        // Bring target-app forrest så fokus er korrekt selv hvis
                        // brugeren klikkede væk mens LLM tænkte.
                        cursor.paste(edited, restoringFocusToPID: editTargetPID)
                        recordHistoryEntryIfAllowed(TranscriptEntry(
                            rawText: transcript.text,
                            processedText: edited,
                            modeId: "edit",
                            durationMs: transcript.durationMs,
                            inferenceMs: transcript.inferenceMs
                        ))
                        state = .idle
                        hud.dismissWithToast(
                            words: edited.split(whereSeparator: { $0.isWhitespace }).count,
                            latencyMs: transcript.inferenceMs,
                            engine: "LM Studio"
                        )
                        wakeWord.resumeAfterRecording()
                        return
                    } catch {
                        log.warning("EditMode fejlede: \(error.localizedDescription, privacy: .public) — skriver instruktion som rå dictation")
                        lastError = "Edit fejlede: \(error.localizedDescription)"
                        cursor.type(instruction)
                    }
                    state = .idle
                    hud.dismiss()
                    wakeWord.resumeAfterRecording()
                    return
                }

                // Inline AI-kommandoer: detektér trigger-frase i slutningen af
                // dictation ("...skriv det som email"). Hvis trigger findes OG
                // LM Studio er klar, splitter vi content fra instruction og kører
                // LM Studio. Skip stenograf + mode-routing — inline-edit overrider.
                // Hvis LM Studio nede: ignorer trigger, fortsæt til normal flow.
                if inlineEditEnabled,
                   lmStudio.isConfigured,
                   let split = InlineEditMode.detectInstruction(correctedText) {
                    log.info("Inline-edit kører — content=\(split.content.count) chars, instruktion=\"\(split.instruction.prefix(60), privacy: .public)\"")
                    lastEngineLabel = "LM Studio"
                    state = .routing
                    let marker = Mode(id: "inline-edit", title: "Redigerer…", triggers: [], systemPrompt: "")
                    hud.update(state: .routing, activeMode: marker)
                    do {
                        let result = try await InlineEditMode.run(
                            content: split.content,
                            instruction: split.instruction,
                            controller: self
                        )
                        cursor.type(result)
                        recordHistoryEntryIfAllowed(TranscriptEntry(
                            rawText: transcript.text,
                            processedText: result,
                            modeId: "inline-edit",
                            durationMs: transcript.durationMs,
                            inferenceMs: transcript.inferenceMs
                        ))
                        state = .idle
                        hud.dismissWithToast(
                            words: result.split(whereSeparator: { $0.isWhitespace }).count,
                            latencyMs: transcript.inferenceMs,
                            engine: "LM Studio"
                        )
                        wakeWord.resumeAfterRecording()
                        return
                    } catch {
                        log.warning("InlineEditMode fejlede: \(error.localizedDescription, privacy: .public) — falder til normal flow")
                        // Fortsæt nedenunder med normal mode-routing på correctedText
                    }
                }

                // Effektiv stenograf: profil har højere prioritet end global setting.
                let effectiveStenograf = profile?.stenografOverride ?? stenografMode

                if effectiveStenograf {
                    // Stenograf-mode: skip alt mode-routing, gå direkte til cursor.
                    let cleanText = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    cursor.type(cleanText)
                    recordHistoryEntryIfAllowed(TranscriptEntry(
                        rawText: transcript.text,
                        processedText: cleanText,
                        modeId: nil,
                        durationMs: transcript.durationMs,
                        inferenceMs: transcript.inferenceMs
                    ))
                    state = .idle
                    hud.dismissWithToast(
                        words: cleanText.split(whereSeparator: { $0.isWhitespace }).count,
                        latencyMs: transcript.inferenceMs,
                        engine: lastEngineLabel ?? (effectiveLanguage.usesCanary ? "Canary" : "Apple Speech")
                    )
                    wakeWord.resumeAfterRecording()
                    return
                }

                state = .routing
                hud.update(state: .routing)
                lastEngineLabel = "LM Studio"

                // Vocabulary kommer FØRST (corrected text), så forced-mode prepender
                // sin trigger på den korrigerede tekst. ModeRouter matcher derved
                // præcis den profil-låste mode selv hvis brugeren ikke siger trigger.
                let effectiveTranscript = applyForcedMode(profile: profile, transcript: correctedText)

                let result: RouteResult
                do {
                    if let preview = modes.previewMatch(for: effectiveTranscript) {
                        hud.update(state: .routing, activeMode: preview)
                    }
                    result = try await modes.route(text: effectiveTranscript, controller: self)
                } catch let modeError as ModeError {
                    log.warning("Mode-routing fejlede, falder tilbage til rå-transkription")
                    lastError = modeError.errorDescription
                    result = RouteResult(text: modeError.fallbackText ?? correctedText, mode: nil)
                }

                cursor.type(result.text)

                recordHistoryEntryIfAllowed(TranscriptEntry(
                    rawText: transcript.text,
                    processedText: result.text,
                    modeId: result.mode?.id,
                    durationMs: transcript.durationMs,
                    inferenceMs: transcript.inferenceMs
                ))

                state = .idle
                hud.dismissWithToast(
                    words: result.text.split(whereSeparator: { $0.isWhitespace }).count,
                    latencyMs: transcript.inferenceMs,
                    engine: result.mode != nil
                        ? "LM Studio"
                        : (effectiveLanguage.usesCanary ? "Canary" : "Apple Speech")
                )
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

    /// Hvis profil har forcedModeId konfigureret, prepend mode'ens første trigger
    /// til transcript så ModeRouter matcher den. Hvis ikke: returnér uændret.
    private func applyForcedMode(profile: AppProfile?, transcript: String) -> String {
        guard let profile, let modeId = profile.forcedModeId else { return transcript }
        let allModes = Mode.builtins + modes.custom
        guard let mode = allModes.first(where: { $0.id == modeId }),
              let firstTrigger = mode.triggers.first else { return transcript }
        // Hvis transcript allerede starter med en trigger, gør ikke noget
        let lower = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if mode.triggers.contains(where: { lower.hasPrefix($0.lowercased()) }) {
            return transcript
        }
        return "\(firstTrigger) \(transcript)"
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
