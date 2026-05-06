# Saga — Roadmap

## Nuværende state (sidst opdateret 2026-05-06)

**Hvad virker end-to-end:** Hold ⌥ → dansk/engelsk/tamilsk dictation med live transkript i HUD. Hold ⇧+⌥ → voice-edit. Sig fx "...skriv det som email" mid-dictation → inline AI-kommando. Sig "Hej Saga"/"Hej Jarvis" → Companion-conversation. Filler-strip + vocabulary fix automatisk transcript før indsætning.

**v0.8.0** tilføjede TranscriptionStats med ord/tegn/lyd-tid/RTF i Settings → Om, live engine-badge ("🔒 Canary"/"Apple Speech"/"LM Studio") + mic-badge i HUD, og 6 designforbedringer i HUD'et (symmetrisk waveform, audio-reactive kant, word-by-word highlight, gradient fade i scroll, idle breathing, stats-toast efter transcribe).

**Faser merged til main:**

| Fase | Status |
|------|--------|
| M0 (scaffold + foundation) | ✅ done |
| M0.B-G (live HUD, persistence, signing, polish) | ✅ done |
| M1 (dictation pipeline) | ✅ done |
| M2 (LM Studio modes — translate/format/summarize/vibecode/linkedin) | ✅ done |
| M3 (voice-reminders via "mind mig om...") | ✅ done |
| M3.B (wake-word "Saga"/"Jarvis" via on-device SFSpeechRecognizer) | ✅ done |
| M4 (vision — multi-modal LLM screen-capture) | ✅ done |
| M5 (document-analysis — PDF/DOCX flagging) | ✅ done |
| M6 (custom modes editor) | ✅ done |
| M6.0 (stenograf-mode toggle) | ✅ done |
| M7 (integrations) | ⏸ skipped per ønske |
| M8 (DMG-distribution + INSTALL/SMOKE_TEST) | ✅ done |
| **CLI-sprint** (TTS, Companion, settings-split, cursor-bubble, live-partial, per-app profiles) | ✅ done |
| **Sprint B** (vocabulary, VAD auto-stop, voice-edit) | ✅ done |
| **Voice-edit v2** (Shift+⌥, clipboard-fallback, Cmd+V paste, target-app re-aktivering, model-picker) | ✅ done |
| **Design-redesign** (Superwhisper-inspired: dark-first tokens, kompakt HUD med hvid waveform + rød REC + keyboard-pills, single-step guided wizard, omvendt-trekant logo) | ✅ done |
| **Wispr-Flow-cleanup** (filler-removal, inline AI-kommandoer, live partial transcribe i HUD, multilingual ASR med tamilsk + 10 EU-sprog, HUD-polish: tynd accent-kant + blødere transparency) | ✅ done |
| **Stats + HUD-polish v2** (TranscriptionStats i Settings → Om, engine-badge + mic-badge i HUD, 6 designforbedringer: symmetrisk waveform, idle breathing, audio-reactive kant, word-by-word highlight, gradient fade, stats-toast) | ✅ done |

**Releases på GitHub:** v0.1.0 (M0+M8), v0.2.0 (M2+M3+M4+M5+M6.0), v0.5.0 (CLI-sprint + Sprint B + voice-edit v2), v0.6.0 (Design-redesign + omvendt-trekant logo), v0.7.0 (Wispr-Flow-cleanup + multilingual + live HUD), v0.8.0 (Stats + HUD-polish v2).

**Næste muligheder:**
- Sideprojekt: hviske-coreml (~10 dage) → drop-in upgrade fra Canary til Hviske
- LICENSE-beslutning hvis open-source senere
- Sparkle-aktivering (placeholder-key skal udskiftes — pt. droppet for solo-tool)

**Cross-Mac development:** se [README.md → "Continuing development"](../README.md#fortsætte-udvikling-fra-en-anden-mac).

---


## M0 — Scaffold (done · 2026-05-04)
- [x] Repo-struktur, GitHub privat repo, README, ARCHITECTURE, ROADMAP
- [x] Swift Package + xcodegen project.yml
- [x] Foundation-kode (Hotkey, Audio, Cursor, Bridge stubs)
- [x] Setup-script

## M0.B — Live status menu + historik (done · 2026-05-04)
- [x] MenuBarExtra med live system-status (Hviske/LM Studio health-rækker)
- [x] Persistent transcript-historik (~/Library/Application Support/Saga/history.json)
- [x] HistoryWindow med søgning + kopier-til-clipboard
- [x] HealthMonitor med periodisk polling

## M0.C — App-launch lifecycle (done · 2026-05-04)
- [x] NSApplicationDelegate sikrer boot ved app-start (ikke kun ved menu-åbning)
- [x] SidecarLauncher.locateUv() søger ~/.local/bin, /opt/homebrew/bin etc.

## M0.D — ASR pivot Hviske → Canary CoreML (done · 2026-05-04)
- [x] Verificeret med rigtig dansk audio: Hviske produced multilingual junk på macOS
- [x] Pivot til canary-coreml (NVIDIA Canary-1b-v2, CoreML/ANE-acceleration)
- [x] Fjernet Python-sidecar (`HviskeBridge`, `SidecarLauncher`)
- [x] Ny `CanaryASRBridge` med samme interface
- [x] HealthMonitor spejler ASRState fra bridge

## M0.E — Robust audio + hotkey (done · 2026-05-04)
- [x] AVAudioEngine → AVAudioRecorder (AVAudioEngine fanget 0 samples på AirPods)
- [x] Hotkey-enum med rightOption/leftOption/rightCommand/rightControl/fn
- [x] AX-permission retry-loop (auto-aktiverer hotkey efter grant)
- [x] Diagnostic logging på info-level med privacy: .public

## M0.F — Stabil signing (done · 2026-05-04)
- [x] CODE_SIGN_IDENTITY pinned til Apple Development cert SHA1
- [x] TCC-permissions overlever rebuilds (csreq tied til cert)

## M0.G — Waveform-HUD (done · 2026-05-04)
- [x] AudioCapture eksposer rolling levelHistory (30 Hz, 48 samples)
- [x] Større HUD (440x145) med frosted glass + capsule-bars
- [x] Live waveform under recording, shimmer under transcribe/route
- [x] Sky-blue accent, rolling tidstæller (s.x → m:ss)
- [x] Symmetrisk gradient-bars, boostet lave levels

## M1 — Dictation pipeline (effectively done via M0.B-G)
End-to-end: Højre Option → tale → Canary → cursor.

**Acceptance:** ✅ Bruger holder ⌥, siger sætning, slipper, ser teksten indsat
i TextEdit/Slack/Claude Code/browser. Verificeret 2026-05-04.

---

## M8 — Distribution (in progress)

Mål: én .dmg som kan dropped på en frisk Mac og virker out-of-the-box.

### M8.A — Hotkey-picker + Apple-keyboard support (done · 2026-05-04)
- [x] Picker-kontrol i Settings → Generelt med alle 5 hotkey-options
- [x] Live reload af event-tap når brugeren ændrer hotkey (ingen restart)
- [x] Help-tekst forklarer hvilke keyboards der virker med hver mulighed
- [x] Apple-keyboard `Fn`-tast er en valid option (kCGEventFlagMaskSecondaryFn)
- [x] Default forbliver Højre Option (universel kompatibilitet)

### M8.B — LM Studio auto-detect (done · 2026-05-04)
- [x] Scan localhost:1234, 1235, 8080, 5000, 11434, 8000 parallelt med 1.5s timeout
- [x] `LMStudioBridge.discover()` returnerer DiscoveredEndpoint-array sorteret efter port
- [x] Auto-configure ved boot: hvis bruger ikke har sat custom URL → tag første fundne
- [x] SettingsView: liste over fundne endpoints med radio-button-valg
- [x] "Find LM Studio igen"-knap til manuel rescan
- [x] Manuel base URL + model TextField bevaret som override
- [x] Verificeret: Saga fandt LM Studio på port 1234 ved boot, log: "fandt 1 endpoints"

### M8.C — DMG distribution (done · 2026-05-04)
- [x] `scripts/build-dmg.sh`: 8-step pipeline med pre-flight, xcodebuild Release, mlpackage-bundling, re-sign, hdiutil, verify
- [x] Bundler mlpackages (1.5 GB encoder + 291 MB decoder + 1.2 MB preprocessor) → Saga.app/Contents/Resources/mlpackage/
- [x] Re-signing efter content-mod via codesign --force --deep med entitlements
- [x] DMG-staging: Saga.app + symlink Applications + Læs mig.txt med install-instruktioner
- [x] hdiutil UDZO compression → 1.7 GB DMG (komprimeret fra 1.8 GB app)
- [x] Verificeret: DMG mounter, Saga.app er signed, mlpackages er bundlet
- [x] Output: `dist/Saga-0.1.0.dmg`

### M8.D — First-run setup wizard (done · 2026-05-04)
- [x] FirstRunWindow.swift: 4-trin onboarding (Sådan virker det / hotkey / permissions / LM Studio)
- [x] Direkte NSWindow via NSHostingController (SwiftUI Window-scenes mounter ikke i MenuBarExtra-kontekst)
- [x] Conditional vises kun hvis UserDefault `firstRunComplete` er false
- [x] StepCard / BulletText / PermissionRow / HelpHint reusable subviews
- [x] Live polling af mic + AX status (Timer 1.5s) → opdaterer "Granté permissions"-knapper
- [x] Hotkey-picker live: ændringer reload event-tap straks
- [x] LM Studio-status: "Søger…" / "Fundet" / "Ingen fundet — installer fra lmstudio.ai"
- [x] "Spring over" + "Kom i gang"-knapper (sidstnævnte disabled før permissions er grantet)
- [x] NSWindowDelegate: marker firstRunComplete også hvis bruger lukker via X-knap
- [x] Verificeret: window åbner ved fresh launch (firstRunComplete=false)

### M8.E — Distribution README + smoke-test (done · 2026-05-04)
- [x] `docs/INSTALL.md` — slutbruger-guide: krav, 3-trins install, Gatekeeper-bypass, fejlfinding, afinstallation, privacy
- [x] `docs/SMOKE_TEST.md` — 7-trins manuel checklist for QA på frisk Mac
  (DMG-mount → first-launch → wizard → dictation → status-menu → settings → persistens)
- [x] README.md har nu separat "Installation (slutbrugere)" + "Setup (udviklere)"
  sektion med link til build-dmg.sh
- [x] Forventet performance-tabel for M-series Mac
- [x] DMG rebuilt med M8.B-D features (auto-detect + first-run wizard) — 1.7 GB

## M2 — LM Studio modes (done · 2026-05-04)
LLM-baserede modes — translate, format, summarize, vibe-code, linkedin.

- [x] `LMStudioBridge` (OpenAI-kompatibel HTTP-klient — done i M0.B)
- [x] `Mode`-protocol + 6 indbyggede implementationer (done i M0.B)
- [x] `ModeRouter` med trigger-word matching (done i M0.B)
- [x] M2-tilføjelser: persistent disabled-set i UserDefaults
- [x] M2-tilføjelser: SettingsView med toggles per mode + test-input/output
- [x] M2-tilføjelser: graceful fallback til rå-transkription hvis LM Studio fejler
- [x] M2-tilføjelser: HUD viser mode-titel under routing (`Mode: Oversæt til engelsk`)
- [x] M2-tilføjelser: ModeError.lmStudioFailed med fallback-text

**Acceptance:** ✅ Bruger kan slå modes til/fra i Settings, teste dem live,
og hvis LM Studio er nede får brugeren rå-transkription i stedet for fejl.


## M3 — Voice-reminders (done · 2026-05-04)
Voice-aktiverede reminders via mode-trigger. Wake-word "Hey Saga" er
udskudt til M3.B (kræver Snowboy/Porcupine eller continuous SFSpeechRecognizer
— udenfor scope for personlig brug).

- [x] `ReminderEngine` ObservableObject — UNUserNotificationCenter scheduling
  + persistens til UserDefaults
- [x] Permission-flow: requestAuthorization med graceful denied-handling
- [x] `ScheduledReminder` model med formattedFireDate (dansk locale, "i dag/i morgen/EEEE")
- [x] `ReminderMode` med trigger-frase ("mind mig om", "remind me to", "påmindelse:")
  som matchet før ModeRouter's generiske matching
- [x] LLM-prompt parser dansk fri-tekst til `{trigger_iso8601, title, body}` JSON
- [x] Markdown-fence-stripping + fallback-formatter til ikke-ISO timestamps
- [x] Confirmation-tekst injected ved cursor: "✓ Reminder: Ring til Lars i morgen kl. 14:00"
- [x] Settings → Reminders-tab: notification-permission-status + liste over upcoming
  med cancel-knap + "Ryd alt"
- [x] HUD viser "Mode: Reminder" under routing

### M3.B — Wake-word (done · 2026-05-04)
- [x] WakeWordDetector med SFSpeechRecognizer (`requiresOnDeviceRecognition=true`)
- [x] Dansk locale med fallback til en-US hvis dansk ikke understøttes lokalt
- [x] Continuous AVAudioEngine input → SFSpeechAudioBufferRecognitionRequest
- [x] Match-fraser: "hej saga", "hey saga", "okay saga"
- [x] Pause/resume API så push-to-talk kan tage over uden konflikt
- [x] Auto-restart ved final-result eller fejl (sessions timer typisk efter ~1 min)
- [x] Settings-toggle "Aktivér 'Hej Saga' wake-word" (default OFF)
- [x] Permission-request via SFSpeechRecognizer.requestAuthorization() med
      auto-disable hvis denied
- [x] handleWakeWordTrigger: simulér Fn-press, auto-stop efter wakeWordRecordingDuration (6 sek)
- [x] NSSpeechRecognitionUsageDescription tilføjet til Info.plist

**Acceptance:** ✅ Med wake-word toggled ON, sig "Hej Saga ring til Lars" →
Saga starter optagelse, transkriberer i 6 sek, indsætter ved cursor.

**Acceptance:** ✅ Sig "mind mig om at ringe til Lars i morgen kl 14"
→ notifikation kommer i morgen kl 14 + bekræftelse skrives ved cursor.

## M4 — Vision (done · 2026-05-04)
Skærm-analyse via multi-modal LLM.

- [x] `ScreenVision` ObservableObject med ScreenCaptureKit (CGWindowList er
  deprecated i macOS 14+). Capture frontmost window eller fuld display.
- [x] CGRequestScreenCaptureAccess() til permission-prompt
- [x] PNG-export via NSBitmapImageRep
- [x] `VisionMode` med 6 trigger-fraser ("hvad ser jeg", "vision:", etc.)
- [x] `LMStudioBridge.chatWithImage()` — OpenAI-format multi-modal payload
  (text + image_url med data:image/png;base64,...)
- [x] 120s timeout på vision-call (langsommere end text-only)
- [x] HUD viser "Mode: Vision" under capture + LLM-call
- [x] VisionError med permissionDenied / captureFailed / visionNotSupported

Forudsætter en vision-capable model er loaded i LM Studio (llava, gemma-4-vision,
qwen2-vl, etc.). gemma-4-26b-a4b text-only fejler på image-input.

**Acceptance:** ✅ Med en webside åben, sig "vision: hvad er dette domæne om?"
→ Saga capturer foran-vinduet, sender til LM Studio, indsætter beskrivelse
ved cursor.

## M5 — Document analysis (done · 2026-05-04)
PDF/DOCX-analyse for binding-perioder, fortrydelsesfrister, automatiske fornyelser.

- [x] `DocumentAnalyzer` ObservableObject med @Published lastResult + isAnalyzing
- [x] File picker via NSOpenPanel (PDF, DOCX, RTF, TXT)
- [x] PDF-extraction via PDFKit (siderwise concat med dobbelt-newline)
- [x] DOCX/RTF via NSAttributedString.init(data:options:documentAttributes:)
  — macOS-built-in, ingen ZIP-extraction nødvendig
- [x] Chunking på paragraph-grænser, max 6000 chars per chunk
- [x] LLM system-prompt med strict JSON-output: 6 kategorier (binding/fortrydelse/
  fornyelse/gebyr/opsigelse/andet) + 3 severity-niveauer (lav/medium/høj)
- [x] Per-chunk LLM-call med "Sektion X af Y"-prefix for kontekst
- [x] Findings-deduplication via title+quote-prefix-signature
- [x] DocumentAnalysisWindow med summary-bar, finding-cards, severity-pills,
  category-icons, citat-blok med textSelection enabled
- [x] StatusView footer-knap: åbner document-vinduet
- [x] Empty/error/no-findings/analyzing states

**Acceptance:** ✅ Vælg PDF/DOCX → modal med fund grupperet efter kategori,
severity-pill, kort forklaring, ordret citat. Analyse tager 30-90s for typisk
kontrakt afhængig af LM Studio-model.

## M6.0 — Stenograf-mode (done · 2026-05-04)
Toggle der skipper ALT routing/LLM/modes — ren dictation til cursor.

- [x] @Published stenografMode i SagaController, persisteret i UserDefaults
- [x] handleHoldEnd skipper modes.route() helt når stenograf er ON
- [x] Settings → Generelt → "Mode"-sektion øverst med toggle + forklaring
- [x] StatusView viser "Klar · Stenograf-mode" når aktiveret
- [x] Loggning af mode-skift

**Acceptance:** ✅ Med stenograf-mode ON sker der INGEN LM Studio-kald,
selv hvis brugeren siger "oversæt til engelsk: hej". Kun ren Canary →
cursor.

## M6 — Custom modes (done · 2026-05-04)
Bruger-defineret modes via Settings.

- [x] `Mode` opdateret til Codable så det kan persisteres som JSON
- [x] ModeRouter `custom: [Mode]` @Published, persisteret i UserDefaults
- [x] addCustom / updateCustom / deleteCustom / generateCustomID public API
- [x] Custom modes vises i ModesSettingsTab over indbyggede med "CUSTOM"-pill
  + edit-pencil-knap
- [x] CustomModeEditor sheet: title, triggers (komma-sep), system-prompt
  (TextEditor), temperature-slider (0-1)
- [x] "Ny custom mode"-knap i ModesSettingsTab toolbar
- [x] Edit + delete via sheet med dynamisk role-button

**Acceptance:** ✅ Bruger opretter "Tweet"-mode med trigger "tweet:" og prompt
"Lav et tweet (max 280 tegn)…". "tweet: vi annoncerer X" → polished tweet
indsat ved cursor. Mode persisterer på tværs af app-restart.

## M7 — Integrations (deferred / skipped)

External webhooks + native macOS apps. Skipped af bruger 2026-05-04 —
Saga's core dictation + modes + reminders + vision + document-analysis er
det meningsfulde scope. Calendar/Sheets/Make-integrationer kan tilføjes
senere som separate add-on-modes ved behov.

- [skip] Webhook-trigger via Make/n8n/zapier
- [skip] Apple Kalender via EventKit (kan implementeres som mode der bruger
        Reminder-engine-style LLM-parsing → EventKit i stedet for UNUNotif)
- [skip] Google Sheets via OAuth + Sheets API
- [skip] Saga URL scheme (`saga://`) for Shortcuts-integration

## M8 — Distribution
Code-sign, notarize, .dmg, auto-update.

- [ ] Apple Developer ID + provisioning profile
- [ ] Embed Python-runtime via `python-build-standalone` (no system Python dep)
- [ ] Embed Hviske model download i first-run flow (eller skip + bruger henter)
- [ ] Notarization via `notarytool`
- [ ] Sparkle auto-update fra GitHub releases
- [ ] Optional: Mac App Store version (kræver fjernelse af AX-features)

**Acceptance:** `make release` producerer signeret notarized `Saga.dmg`.

## Backlog (post-v0.5.0)
- Multi-language support beyond da/en
- Cloud-backup af custom modes (E2E-encrypted)
- iOS companion app (modes-sync via iCloud)
- Plugin-system for community-modes
- Sparkle auto-update aktivering (kræver SUPublicEDKey-genering, pt. droppet)
- LICENSE-beslutning hvis open-source senere
- hviske-coreml sideprojekt (~10 dage) — drop-in upgrade fra Canary

---

## CLI-sprint (done · 2026-05-05)

Stort sprint udført fra anden Mac (CLI-only Claude Code, ingen Xcode), ~7000 linjer
Swift fordelt på ~32 nye filer. Build verificeret efterfølgende på Xcode-Mac.

### TTS infrastructure
- [x] `TTSCoordinator` med engine-selection (Apple AVSpeechSynthesizer eller ElevenLabs)
- [x] `AppleTTSEngine` — on-device, no-cost, default
- [x] `ElevenLabsTTSEngine` — bedre kvalitet, kræver API-key i Keychain
- [x] Voice-picker for Apple-stemmer (Sara, Magnus, Ida, Naja)
- [x] Reachability-tjek + auto-fallback til Apple hvis ElevenLabs nede
- [x] Voice-ID sanitization (forhindrer corruption fra cursor-inject)

### Companion conversation
- [x] `CompanionController` state-machine: idle → listening → transcribing → thinking → speaking
- [x] `CompanionSession` med trim-logik (max-turn-pairs) + system-prompt
- [x] Streaming `chatStream()` med SSE → `SentenceFlusher` deler ved punktum
- [x] TTS starter ved første sætning i stedet for at vente på fuldt svar
- [x] Live caption-overlay med transcript-historik (CompanionOverlay)
- [x] Cursor-bubble: pulserende prik der følger musen mens Saga lytter
- [x] Auto-end ved end-of-session-frase ("tak", "farvel", "stop") — bruger prefix-match
- [x] Vision-context: screenshot vedhæftes user-tur hvis modellen er multi-modal

### Settings split
- [x] SettingsView refaktor til 7 separate tabs (Generelt/Stemme/Modes/Apps/Companion/Reminders/Om)
- [x] Reusable building blocks (SettingsCard + SettingsRow)
- [x] AboutTab med model-storage + update-card

### Per-app profiles
- [x] `AppProfile` med bundleId-binding + forcedModeId + stenografOverride
- [x] AppProfileStore — JSON-persistens i UserDefaults
- [x] AppProfilesSettingsTab UI — opret/edit profiles for installerede apps
- [x] SagaController.applyForcedMode prepender mode-trigger ved transcribe-tid

### Live partial transcript
- [x] `LivePartialTranscriber` via SFSpeechRecognizer parallel med Canary
- [x] Vises i Companion-overlay mens bruger taler
- [x] Erstattes med Canary's authoritative transcript ved turn-end

### Slim-DMG + ModelDownloader
- [x] `ModelDownloader` med progress + resume + reset
- [x] First-run flow: hvis mlpackages mangler i bundle, download fra GitHub Release-assets
- [x] ModelStorageCard i AboutTab viser disk-brug + reset-knap

## Sprint B (done · 2026-05-05)

Power-user features fra parallel branch, rebased onto main efter CLI-sprint.

### Vocabulary post-processor
- [x] `VocabularyEntry` Codable struct (pattern, replacement, caseSensitive, wholeWord, enabled, notes)
- [x] `VocabularyStore` med UserDefaults JSON-persistens
- [x] `VocabularyPostProcessor` med regex-baseret apply (escapes specielle tegn)
- [x] VocabularySettingsTab — entry-list, editor-modal, master enable, "Slet alle" med confirm
- [x] Anvendes på alle Canary-transcripts FØR mode-routing + stenograf

### VAD auto-stop
- [x] `EnergyVAD` — energi-baseret silence detection
- [x] `VADConfig` med silenceThreshold + silenceDuration + minRecordingDuration
- [x] AudioCapture wires VAD callback → handleHoldEnd
- [x] Settings-toggle + slider (0.5-3.0s tærskel)

### Voice-edit (initial trigger-frase version)
- [x] `EditMode` med "ret:"/"redigér:"/"rewrite:"/"edit:" triggers
- [x] `SelectionReader` via AXUIElement (kAXSelectedTextAttribute)
- [x] ModeRouter integration: special-cased før mode-matching, falder til normal hvis ingen selection
- [x] Strict system-prompt: "Returnér KUN den redigerede tekst"

## Voice-edit v2 (done · 2026-05-05)

Trigger-fraser viste sig fragile: ASR transkriberer "ret kolon" som ord, ikke
som ":". Iteration efter real-world test i Claude-app.

- [x] **Shift+⌥ som trigger** — eksplicit modifier i stedet for trigger-frase
- [x] HotkeyManager.onHoldStart får shiftHeld-bool, læser `flags.contains(.maskShift)` på CGEvent
- [x] **Clipboard-fallback** for Electron-apps (Claude, Slack, VSCode, Notion) der ikke
      eksponerer kAXSelectedText: simulér Cmd+C, læs pasteboard, gendan oprindeligt indhold
- [x] **Cmd+V paste** i stedet for unicode-keyboard-injection — pålideligt i Electron-apps
- [x] **Target-app re-aktivering** — husk frontmost PID ved hold-start, bring forrest før paste
      (brugeren kan kigge på LM Studio under tænkning uden at miste fokus)
- [x] **HUD viser "Redigerer…"** under hele LM Studio-tænkning (op til 60s for store models)
- [x] **Reasoning-only response detection** — gemma-thinking-modeller spiser hele max_tokens på
      reasoning_content. LMStudioBridge throws specifik fejl med konkret guide til fix
- [x] **max_tokens=8192** for EditMode (default 2048 var for lidt med reasoning-modeller)
- [x] **Model-picker** i VoiceSettingsTab — radio-buttons for alle modeller fundet på det aktive
      LM Studio-endpoint, klik = øjeblikkelig reconfigure uden restart

## v0.5.0 — Release (done · 2026-05-05)

DMG bygget med alle ovenstående features. 1.7 GB med bundlede mlpackages.
Cumulativt fra v0.2.0: CLI-sprint + Sprint B + voice-edit v2 + jarvis-wake + tak-detection
+ saga-sidecar slettet + Sparkle deaktiveret (placeholder-key).

## Design-redesign (done · 2026-05-06)

Superwhisper-inspireret visuel re-design af alle UI-flader. Dark-first
æstetik der ignorerer system-tema (.preferredColorScheme(.dark) på alle
vinduer). Centraliseret design-token-fil til konsistens på tværs.

### Design-system foundation
- [x] `SagaTheme.swift`: SagaColors (background/surface/surfaceElevated/border +
      textPrimary/Secondary/Tertiary + accent (RGB 0.40,0.70,1.0) + accentSubtle/
      Border + success/warning/danger), SagaTypography (display/title/heading/
      body/bodyEmphasis/caption/label/mono), SagaRadii (small=8/medium=12/
      large=16/xl=20/pill=999), SagaSpacing (xs=4 til xxl=32), SagaShadow
      (subtle/medium/glow)
- [x] `SagaButton.swift`: SagaButtonStyle med .primary/.secondary/.ghost/
      .destructive — full-width 44pt høj med large corner-radius
- [x] `KeyboardPill.swift`: Inline keyboard-shortcut hint med monospace-font
      som "[⌥] Stop" eller "[⇧+⌥] Edit"
- [x] `ProgressBar.swift`: WizardProgressBar (3pt høj, accent-gradient-fyldt
      fraktion) til top af wizard

### First-run wizard refactor
- [x] Single-step state-driven wizard med 5 trin (Velkommen → Permissions →
      Mic-test → Hotkey → LM Studio) — én ting ad gangen, progress-bar i top,
      full-width primary CTA i bunden
- [x] Welcome-step med stort waveform-icon i sky-blue gradient + glow-shadow
- [x] Permissions-step med 2 NewPermissionRow (mic + AX) — icon-circle, titel,
      detail, Allow/Settings-button
- [x] Mic-test-step med live waveform via AudioCapture.levelHistory
- [x] Hotkey-step med 5 HotkeyOption rows (radio-style cards med accent-border
      ved selected)
- [x] LM Studio-step med 2 ChoiceCard (Kun lokal vs Lokal + LM Studio) +
      live discovery-status

### Recording HUD redesign (3 iterations baseret på brugerfeedback)
- [x] **v1**: dark-first colors + keyboard-pills + esc-cancel-funktion
- [x] **v2**: kompakt 2-row layout (480x110, ~37% lavere) — full-width waveform
      i top, logo+timer+pills i bottom-bar
- [x] **v3 (final)**: hvid waveform (SagaColors.textPrimary), rød pulserende
      REC-dot (RecordingDot view med ring-effekt), timer i midten via ZStack,
      mindre dead-space (outer padding 8→4), 100 tynde 1.5pt-bars med per-bar
      pseudo-random variation + center-bias + linear-gradient fade-mask i
      kanterne (matcher Superwhisper's polished look)
- [x] SagaController.cancelRecording() — esc afbryder uden ASR-kald
- [x] Hotkey.keySymbol — kompakt symbol til keyboard-pills (⌥/⌘/⌃/fn)

### Companion overlay re-skin
- [x] Mørk solid baggrund (SagaColors.surfaceElevated 0.85) i stedet for
      ultraThinMaterial. Matcher RecordingHUD's look
- [x] Større typografi (12pt → 14pt body) for bedre læsbarhed
- [x] KeyboardPill "[sig 'tak'] for at afslutte" erstatter den gamle
      inline-capsule-hint

### Settings tabs dark-first
- [x] TabView root med .preferredColorScheme(.dark) + SagaColors.background
- [x] Window 640x620 → 720x680 for større typografi
- [x] SettingsCard: surface-baggrund, large corner-radius, label-typografi
- [x] SettingsRow: bodyEmphasis title (14pt), caption subtitle, større padding
- [x] Alle 7 tabs (Generelt/Stemme/Modes/Apps/Companion/Ordforråd/Reminders/
      Om) arver automatisk det nye look via SettingsCard+SettingsRow

### Branding: omvendt trekant som logo
- [x] Menubar-icon: `triangle.fill` roteret 180° = omvendt trekant. Symbol-
      effects per state (.pulse under recording, .variableColor.iterative
      under transcribing/routing). Erstatter den tidligere state-skiftende
      SF Symbol — én konsistent identitet
- [x] App-icon: hvid omvendt trekant på olivengrøn baggrund (RGB 88,116,56).
      Genereret som standard `.icns` med 10 sizes (16-1024px) via iconutil
- [x] CFBundleIconFile: AppIcon i Info.plist
- [x] Resources/AppIcon.icns tilføjet til target sources i project.yml

## v0.6.0 — Release (done · 2026-05-06)

DMG bygget med Design-redesign + nye logo. Cumulativt fra v0.5.0:
Superwhisper-inspireret dark-first UI på alle flader + omvendt-trekant logo
overalt (menubar + app-icon).

## Wispr-Flow-cleanup (done · 2026-05-06)

Wispr-Flow-inspirerede AI-cleanup-features lagt oven på Canary's transcript.
Fokus: gør dictation pænere out-of-the-box uden at sende noget til skyen.

### Filler-word removal
- [x] `FillerWordRemover.swift`: regex-baseret strip af danske pauseord
- [x] To kategorier: sikre (øh, øhm, øhh, ehm, ehh, eh) der altid strippes,
      og kontekst-sensitive (altså, ligesom, sådan set, hvad hedder det)
      der kun strippes som standalone interjektion
- [x] Cleanup: collapse whitespace, fjern duplikerede kommaer, capitalize
- [x] 16 unit-tests dækker edge cases + brugerord-tilføjelse via UserDefaults
- [x] Settings → Generelt → "Strip pauseord" toggle (default ON)

### Inline AI-kommandoer
- [x] `InlineEditMode.swift`: detektér trigger-frase i suffix-position
      ("...skriv det som email", "...lav det til punktopstilling" osv.)
- [x] 15 trigger-fraser dækker email/punktopstilling/formelt/kortere/længere
- [x] NSRegularExpression med alle triggers OR'd sammen, sorteret længste
      først så regex-engine foretrækker mest specifikke match
- [x] Word-boundary via lookbehind for whitespace/punktuation
- [x] Splitter content fra instruction og kører LM Studio (max_tokens 4096)
- [x] HUD viser "Redigerer…" mens LM Studio arbejder
- [x] Hvis LM Studio ikke konfigureret: trigger ignoreres helt
- [x] 12 unit-tests dækker case-insensitivity, multiple triggers,
      empty content, word-boundary, last-wins
- [x] Settings → Modes → "Inline AI-kommandoer"-card med toggle + trigger-list

### Live partial transcribe i HUD
- [x] `LivePartialTranscriber` kører nu også under almindelig dictation
- [x] Apple's SFSpeechRecognizer parallel med Canary
- [x] @Published `currentPartial` i SagaController
- [x] HUD viser partial-tekst i en ScrollView ovenover waveform
- [x] Auto-scroll til bunden ved hver opdatering — bruger ser altid det
      seneste der er sagt selv ved længere dictation
- [x] Erstattes af Canary's authoritative transcript ved release
- [x] LivePartialTranscriber.setLocale matcher activeLanguage så live er
      på det rigtige sprog (også tamilsk hvis valgt)

### Multi-language ASR med tamilsk
- [x] `AppleSpeechBridge.swift`: SFSpeechRecognizer-wrapper for sprog
      Canary ikke supporterer (særligt tamilsk ta-IN/ta-LK)
- [x] Thread-safe ResumeGuard sikrer CheckedContinuation kun resumes én
      gang ved race mellem callback og 60s timeout
- [x] `MultilingualASRRouter.swift`: vælger Canary eller Apple Speech
      baseret på sprog-kode. Canary supporterer { da, en, de, es, fr, it,
      pt, nl, pl, ru, cs, sk, hu, ro, bg, hr, sr, sl, el, et, lv, lt, fi,
      sv, no }, andre sprog routes til Apple
- [x] `SagaLanguage` enum: 11 sprog initially (dansk default, engelsk,
      tamilsk, tysk, spansk, fransk, italiensk, hollandsk, svensk, norsk,
      finsk). Per-sprog: canaryCode, appleLocale, displayName, qualityLabel
- [x] @Published activeLanguage i SagaController + UserDefaults-persistens
- [x] AppProfile.languageCode: per-app sprog-override (fx WhatsApp altid
      tamilsk, Slack altid engelsk)
- [x] Settings → Stemme → "Sprog"-card med picker over alle 11 sprog
- [x] Settings → Apps → AppProfileEditor → "Sprog-override"-felt

### HUD design-polish (5 iterations baseret på brugerfeedback)
- [x] **iter 1**: live partial-tekst lagt på som overlay ovenpå waveform
- [x] **iter 2**: skifte til VStack — partial OVER waveform (ikke overlay)
- [x] **iter 3**: ScrollView + ScrollViewReader for auto-scroll til bunden
- [x] **iter 4**: opacity 0.88 → 0.55 → 0.18 (drastisk mere transparent)
- [x] **iter 5**: thinMaterial + drop tint + tynd accent-kant (1.2pt, 60%)
      Drop accent-glow helt — kun border + drop shadow tilbage. Window
      500x165, outer padding 12. KeyboardPills 10pt mono med Color.white
      .opacity(0.08) baggrund (var solid mørk panel)

## v0.7.0 — Release (done · 2026-05-06)

DMG bygget med Wispr-Flow-cleanup + multilingual + live HUD + design-polish.
Cumulativt fra v0.6.0: filler-strip, inline AI-kommandoer, live transcribe
i HUD, tamilsk + 10 EU-sprog, og HUD med tynd accent-kant + transparent
glas-følelse.

## Stats + HUD-polish v2 (done · 2026-05-06)

12 commits efter v0.7.0 fokuseret på statistik-feature og HUD-finpudsning.

### Transcription stats
- [x] `TranscriptionStats` Codable struct med totalWords, totalCharacters,
      totalAudioSeconds, totalRecordings, totalInferenceMs, firstUsedAt,
      lastUsedAt. Computed: averageInferenceSeconds, realTimeFactor (RTF)
- [x] `TranscriptionStatsStore`: @MainActor ObservableObject med JSON-
      persistens i UserDefaults. record() opdaterer ved hver successful
      transcribe; reset() til "Nulstil"-knap
- [x] SagaController @Published lastTranscribeMs + lastEngineLabel sat
      ved hver transcribe-completion
- [x] StatsCard i Settings → Om med ord/tegn/lyd-tid/optagelser/latens/RTF/
      siden + grøn "Alt processet lokalt — 0 bytes sendt til skyen"-row
- [x] Footer: "Alt transcriberet 100% lokalt på din Mac"

### Engine + mic-badges i HUD
- [x] `EngineBadge` view: lille kapsel "🔒 Canary"/"Apple Speech"/"LM Studio"
      med accent-tint baggrund (12% opacity) + 30% border. Lock-ikon
      signalerer at engine kører lokalt + tooltip på hover
- [x] `MicrophoneBadge` view: "🎤 AirPods Pro"/"MacBook Pro"/etc. White-
      tint baggrund. Smart label-shortening (fjern "Microphone"/"(USB)"-
      suffix). lineLimit(2) + maxWidth 110 så lange device-navne wrapper
- [x] AudioCapture.currentInputDeviceName via AVCaptureDevice.default.
      Computed property — opdateres automatisk ved mic-skift
- [x] Bottom-bar status i 2 linjer: timer øverst, [Engine] [Mic] nederst

### 6 HUD designforbedringer
- [x] **#1 Symmetrisk waveform fra center-linje** — bars vokser fra
      center op + ned med ±8% mikro-variation. Subtil 0.5pt accent-tinted
      center-line. Top-capsule fuld accent, bottom 85% opacity for dybde
- [x] **#2 Idle breathing** — pulserende capsule (35-65% opacity, 85-100%
      scale) over 4-sek cycle (autoreverses). Signalerer "Saga er klar"
- [x] **#3 Audio-reactive accent-kant** — opacity scales 35-95% med
      rolling avg af sidste 5 audio-samples. Easeout 0.18s animation
- [x] **#4 Gradient fade i partial-text** — LinearGradient mask gør
      øverste linjer i scroll til 0-40% opacity → "tekst kommer fra bunden"
- [x] **#5 Word-by-word highlight** — String.commonPrefix detekterer nye
      ord i partial. AttributedString render hvor suffix er accent-farvet
      i ~700ms før fade til hvid via highlightTask Task.sleep
- [x] **#6 Stats-toast efter transcribe** — RecordingHUDModel.CompletionToast
      struct + dismissWithToast(words:latencyMs:engine:). HUD bevares 1.5s
      efter cursor.type med ✓ "N ord indsat · 850ms · 🔒 Canary"

### Layout-polish
- [x] Stop-pille fjernet (slip af hotkey er naturlig stop)
- [x] Kun esc/Annuller-pille under recording (mindre kendt funktion)
- [x] MicrophoneBadge bruger RoundedRectangle (radius 8) i stedet for
      Capsule (Capsule giver oval-form ved 2-linje content)
- [x] Bottom-bar VStack med timer øverst + badges nederst i HStack

## v0.8.0 — Release (done · 2026-05-06)

DMG bygget med stats-feature + 6 HUD-designforbedringer + engine/mic-badges.
Cumulativt fra v0.7.0: TranscriptionStats med RTF/word-counter, engine-
badge med lock-ikon der signalerer lokal-først, mic-badge med smart
device-name-cleanup, og polishet HUD med symmetrisk waveform + word-
highlight + idle breathing + completion-toast.
