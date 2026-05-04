# Saga — Roadmap

## M0 — Scaffold (done · 2026-05-04)
- [x] Repo-struktur, GitHub privat repo, README, ARCHITECTURE, ROADMAP
- [x] Swift Package + xcodegen project.yml
- [x] Python sidecar med uv-pyproject + Hviske wrapper-skeleton
- [x] Foundation-kode (Hotkey, Audio, Cursor, Bridge stubs)
- [x] Setup-script

## M1 — Dictation pipeline (next)
End-to-end: Fn-tast → tale → Hviske → cursor.

- [ ] Færdiggør `HotkeyManager` (CGEventTap, Fn-detection, key-down/up state)
- [ ] Færdiggør `AudioCapture` (AVAudioEngine, 16kHz resample, PCM-output)
- [ ] Hviske server: download model, test transcribe, FastAPI POST /transcribe
- [ ] `HviskeBridge`: multipart POST audio som WAV bytes
- [ ] `CursorInjector`: CGEvent unicode typing med UTF-16 chars
- [ ] `RecordingHUD`: lille overlay window med mic-icon + audio level
- [ ] `SidecarLauncher`: Process-spawn, /health-poll, restart-on-crash
- [ ] `MenubarController`: status bar icon (idle / recording / error states)
- [ ] Permission flow: mic + accessibility prompts + System Settings deeplink
- [ ] End-to-end manuel test

**Acceptance:** Brugeren kan holde Fn, sige en sætning, slippe, og se teksten
indsat i TextEdit/Slack/hvor som helst cursor er.

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
