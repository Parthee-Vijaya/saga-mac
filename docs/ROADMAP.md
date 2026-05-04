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

### M8.E — Distribution README + smoke-test
- [ ] INSTALL.md med Gatekeeper-bypass-instruktioner
- [ ] Smoke-test checklist på frisk Mac (Air, Pro, Studio)
- [ ] Versionering via tag + GitHub Releases

## M2 — LM Studio modes
LLM-baserede modes — translate, format, summarize, vibe-code.

- [ ] `LMStudioBridge` (OpenAI-kompatibel HTTP-klient)
- [ ] `Mode`-protocol + indbyggede implementationer:
  - [ ] `TranslateMode` (da↔en, da↔es, etc.)
  - [ ] `FormatMode` (clean dictation: punctuation, capitalization)
  - [ ] `SummarizeMode` (TL;DR af lang dictation)
  - [ ] `VibeCodeMode` (NL → AI-prompt for Lovable/Claude Code)
- [ ] `ModeRouter` — trigger-word parser ("oversæt til X", "opsummer", "kode:")
- [ ] Fallback: hvis LM Studio er nede → vis fejl + fall back til pure dictation
- [ ] Mode-vælger i Settings (toggle hver mode on/off)

**Acceptance:** Sig "oversæt til engelsk: hej verden" → "Hello world" indsættes.

## M3 — Hey Saga + reminders
Wake-word + voice-aktiverede reminders.

- [ ] Wake-word: enten Snowboy/PocketSphinx eller en let custom Hviske-loop med
      VAD (research nødvendig — Hviske er for tung til at køre konstant)
- [ ] Alternative: bruger trykker Fn-Fn (double-tap) for "Hey Saga"-mode
- [ ] `ReminderEngine` — UNUserNotificationCenter scheduling
- [ ] `ReminderMode` — LLM ekstraherer { trigger, title } fra dansk fri-tekst
- [ ] Voice-confirm via `AVSpeechSynthesizer` (dansk stemme)

**Acceptance:** Sig "Hey Saga, mind mig om at ringe til Lars i morgen kl 14"
→ notifikation kommer kl 14 dagen efter.

## M4 — Vision
Skærm-analyse via multi-modal LLM.

- [ ] `ScreenVision` — `CGWindowListCreateImage` for active window
- [ ] Multi-modal LM Studio call (gemma-4-26b er multi-modal, eller
      LM Studio-vision-model som llava)
- [ ] Trigger: "Hey Saga, hvad ser jeg her?" → screenshot + LLM-spørgsmål
- [ ] Settings: privacy-toggle for at kræve eksplicit confirm før screenshot

**Acceptance:** Med en webside åben, sig "hvad er dette domæne om?" → korrekt
beskrivelse indsat ved cursor.

## M5 — Document analysis
PDF/DOCX-analyse for binding-perioder, fortrydelsesfrister, automatiske fornyelser.

- [ ] File picker via `NSOpenPanel`
- [ ] PDF-parsing via `PDFKit`
- [ ] DOCX-parsing via custom XML eller bundlet Python-helper
- [ ] `DocumentAnalyzeMode` — chunking + LLM med specialized system prompt
      ("flag binding-perioder, fortrydelsesfrister, automatiske fornyelser,
      skjulte gebyrer")
- [ ] Resultat-view: side-by-side dokument + flagged spans

**Acceptance:** Drop en kontrakt-PDF på Saga → modal med 5 flagede klausuler
+ deres lokation i dokumentet.

## M6 — Custom modes
Bruger-defineret modes via Settings.

- [ ] Mode-editor i Settings: navn, trigger-ord, system-prompt, output-routing
      (cursor / clipboard / webhook)
- [ ] Lokal storage som JSON i UserDefaults
- [ ] Templates: "LinkedIn-post", "Slack-message", "Email-svar i Pavi-stil"

**Acceptance:** Bruger opretter "LinkedIn-mode" med specialized system-prompt;
"linkedin: vi annoncerer X" → polished LinkedIn-post indsat.

## M7 — Integrations
External webhooks + native macOS apps.

- [ ] Webhook-trigger via Make/n8n/zapier (POST til user-defined URL)
- [ ] Apple Kalender via EventKit (opret events fra dictation)
- [ ] Google Sheets via OAuth + Sheets API (append rows)
- [ ] Saga URL scheme (`saga://`) for Shortcuts-integration

**Acceptance:** Sig "tilføj til kalender: tandlæge tirsdag kl 10" → event
oprettet i default kalender.

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
