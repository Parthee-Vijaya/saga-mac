# Saga — Roadmap

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

### M3.B — Wake-word (deferred)
Snowboy er deprecated, Porcupine kræver kommerciel licens. Continuous
SFSpeechRecognizer er cloud-afhængig medmindre `requiresOnDeviceRecognition=true`
hvilket har dårlig kvalitet. Realistisk indsats: ~3-5 dage. Foreløbig: brug
Højre Option + sig "mind mig om...".

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

## M6 — Custom modes
Bruger-defineret modes via Settings.

- [ ] Mode-editor i Settings: navn, trigger-ord, system-prompt, output-routing
      (cursor / clipboard / webhook)
- [ ] Lokal storage som JSON i UserDefaults
- [ ] Templates: "LinkedIn-post", "Slack-message", "Email-svar i Pavi-stil"

**Acceptance:** Bruger opretter "LinkedIn-mode" med specialized system-prompt;
"linkedin: vi annoncerer X" → polished LinkedIn-post indsat.

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

## Backlog (post-M8)
- Multi-language support beyond da/en
- Whisper-large-v3 fallback hvis Hviske ikke kan loades
- Cloud-backup af custom modes (E2E-encrypted)
- iOS companion app (modes-sync via iCloud)
- Plugin-system for community-modes
