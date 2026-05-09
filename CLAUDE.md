# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo-overblik

Saga er en macOS status-bar voice-assistant skrevet i **Swift 6 / SwiftUI** med `LSUIElement=true` (ingen dock-icon). ASR kører fuldt on-device via CanaryKit (NVIDIA Canary-1b-v2 → CoreML). LLM-features (modes, voice-edit, Companion) er valgfrie og bruger lokal LM Studio over HTTP. Ingen cloud, ingen telemetri.

Repoet indeholder **kun Saga-appen**. CanaryKit (Swift Package med CoreML-modeller) leveres af søsterrepoet `canary-coreml/` som forventes at ligge ved siden af dette repo:

```
~/projekter/
├── saga/             ← dette repo
└── canary-coreml/    ← Swift Package + .mlpackage-modeller
```

`saga-app/project.yml` peger på `../../canary-coreml/swift` som SPM-path. Hvis `canary-coreml/` mangler, kan Saga ikke bygge.

## Kommandoer

### Setup på frisk maskine
```bash
brew install xcodegen
cd saga-app && xcodegen generate    # genererer SagaApp.xcodeproj fra project.yml
open SagaApp.xcodeproj               # Cmd+R bygger + kører
# eller: ./scripts/setup.sh
```

`*.xcodeproj/` er gitignored — **regenerér altid med `xcodegen generate`** før første build, og igen når `project.yml` har ændret sig (nye source-filer, nye dependencies, ændret bundle-config).

### Build / test fra CLI
```bash
# Build Release
cd saga-app && xcodegen generate
xcodebuild -project SagaApp.xcodeproj -scheme Saga -configuration Release build

# Kør hele test-suiten (Swift Testing framework)
xcodebuild -project SagaApp.xcodeproj -scheme Saga test \
  -destination "platform=macOS"

# Kør én testfil
xcodebuild -project SagaApp.xcodeproj -scheme Saga test \
  -destination "platform=macOS" \
  -only-testing:SagaCoreTests/ModeRouterTests
```

### Bygge DMG til distribution
```bash
./scripts/build-dmg.sh                  # full DMG (~1.8 GB, mlpackages bundlet)
SAGA_SLIM=1 ./scripts/build-dmg.sh      # slim DMG (~12 MB, modeller downloades ved 1. start)
# Output: dist/Saga-X.Y.Z.dmg (version trækkes fra MARKETING_VERSION i project.yml)
```

DMG-scriptet kræver at `../canary-coreml/models/mlpackage/` eksisterer (eller `SAGA_SLIM=1`). Override path med `SAGA_CANARY_DIR=...`. Re-signer med Apple Development cert (SHA1 i `project.yml`); falder tilbage til ad-hoc hvis cert mangler.

## Arkitektur

### Top-level

`SagaAppMain.swift` (target `Saga`) er ren SwiftUI App-skel: én MenuBarExtra + Settings-scene + history/document-windows. Al logik lever i `SagaController` som er én `@MainActor ObservableObject` der ejer alle moduler og koordinerer dem.

`SagaController.bootIfNeeded()` (App/SagaController.swift) er entry-point — kører ved `applicationDidFinishLaunching` og:
1. Loader CoreML-modellen i baggrunds-task (cold-start ~10s, warm <1s)
2. Wirer `HotkeyManager.onHoldStart/onHoldEnd` til recording-livscyklus
3. Wirer `WakeWordDetector.onWake` til Companion eller dictation alt efter setting
4. Auto-discovery af LM Studio på localhost (probes `commonPorts = [1234, 1235, 8080, 5000, 11434, 8000]`)

### Recording-flow (hot path)

`handleHoldStart` → `audio.start()` + start `LivePartialTranscriber` (Apple SFSpeechRecognizer parallel) → `handleHoldEnd` → `asrRouter.transcribe()` → vocabulary post-processing → filler-strip → snippet-expansion → `ModeRouter.route()` → `cursor.paste()` eller `cursor.typeAtCursor()`.

`MultilingualASRRouter` (Bridge/) vælger mellem `CanaryASRBridge` (dansk + 25 EU-sprog), `HviskeASRBridge` (dansk premium — stub indtil hviske-coreml er færdigt) og `AppleSpeechBridge` (tamilsk + andre) baseret på `effectiveLanguage` plus `preferredDanishEngine`. Routing-prioritet: dansk + Hviske valgt + Hviske ready → Hviske; ellers Canary hvis supporteret; ellers Apple Speech. Hviske-bridgen er en stub der altid kaster `notReady` indtil søsterprojektet `~/projekter/aktive/hviske-coreml/` er gennem F1-F8 (se dets HANDOFF.md). Saga's UI har allerede picker i Settings → Voice → "Dansk ASR-engine".

Hvis brugeren holdt **Shift+hotkey**, snapshot'er controlleren markeret tekst FØR recording (via `SelectionReader` — AX-API + clipboard-fallback for Electron-apps), husker target-PID, og kører `EditMode.run()` direkte i stedet for mode-routing. Target-app re-aktiveres FØR paste så fokus er korrekt selv hvis brugeren klikkede væk mens LLM tænkte.

### ModeRouter

`ModeRouter.route()` har en fast prioritetsrækkefølge: `ReminderMode` → `CalendarMode` → `VisionMode` → `OdinMode` → `EditMode` → trigger-prefix-match mod `Mode.builtins + custom`. Hvis intet match: `IntentClassifier.looksLikeIntent` heuristik kører LLM-fallback (Canary mishør "mind mig om" → "Det regnede" på dansk, så streng prefix-match alene er ikke nok).

Built-in modes er hardcoded array i `Mode.builtins` (Modes/ModeRouter.swift). Custom modes persisteres som JSON i UserDefaults under `modeRouter.custom`. Hver Mode kan have multi-shot `examples: [ModeExample]` (input/output-par sendt til LLM som few-shot learning).

`ReminderMode` og `CalendarMode` kører **lokalt via EventKit** — ingen LLM. De parser danske tids- og handlings-keywords og opretter EKReminder/EKEvent direkte. `VisionMode` kalder multi-modal LLM med `ScreenVision` screen-capture. `OdinMode` kalder Odin RAG-daemon på localhost:3838.

### Modul-organisering (Sources/SagaCore/)

| Mappe | Ansvar |
|---|---|
| `App/` | `SagaController` — top-level orkestrator |
| `Audio/` | `AudioCapture` (AVAudioRecorder), `VADDetector` (auto-stop ved stilhed), `LivePartialTranscriber` (SFSpeech parallel-transcribe under hold) |
| `Bridge/` | `CanaryASRBridge`, `HviskeASRBridge` (stub), `AppleSpeechBridge`, `MultilingualASRRouter` (vælger engine + sprog), `LMStudioBridge` (OpenAI-kompatibel HTTP-klient med discovery) |
| `Calendar/`, `Reminders/` | EventKit-baseret intent-håndtering (ingen LLM påkrævet) |
| `Companion/` | Wake-word-aktiveret samtale-mode med `SentenceFlusher` (chunker partial transcripts ved sætnings-grænser for streaming TTS) |
| `Cursor/` | `CursorInjector` — Cmd+V paste vs. CGEvent unicode-typing baseret på frontmost-app (Electron-detection) |
| `History/` | `HistoryStore` (JSON i `~/Library/Application Support/Saga/`), `JournalStore` (~/Saga-journal/YYYY-MM-DD.md), `TranscriptionStats` |
| `Hotkey/` | `HotkeyManager` — CGEventTap på modifier-keys |
| `Modes/` | Mode-routing + IntentClassifier (LLM-fallback når trigger-prefix ikke matcher) |
| `Profiles/` | Per-app overrides (mode-defaults, sprog) — frontmost app polled ved hold-start |
| `TTS/` | Apple AVSpeechSynthesizer + ElevenLabs HTTP-bridge |
| `UI/` | StatusView (menubar dropdown), HUD, Settings tabs (`UI/Settings/`), DesignSystem tokens (`UI/DesignSystem/SagaTheme.swift`) |
| `Vocabulary/` | Custom dictionary post-processor, filler-word remover, snippets med iCloud Drive sync |
| `WakeWord/` | `WakeWordDetector` — on-device SFSpeechRecognizer kontinuerligt lyttende efter "Hej Saga"/"Hej Jarvis" |

### Persistence

- **UserDefaults**: feature-toggles, sprog-valg, custom modes (JSON), disabled built-in mode-IDs, LM Studio config
- **`~/Library/Application Support/Saga/`**: history.json, models/ (slim-DMG download-target), profiles
- **`~/Saga-journal/YYYY-MM-DD.md`**: daglig voice-journal (opt-in)
- **iCloud Drive** (valgfri): snippet-bibliotek synket på tværs af Macs
- **Keychain**: ElevenLabs API-key (via `KeychainStore`)

`privacyMode` er en runtime-flag — IKKE persisteret. Når aktiv: skip `history.append`, `stats.record`, `journal.append`. Wrapper-metoden `recordHistoryEntryIfAllowed` bruges fra alle 4 success-paths i `handleHoldEnd`.

## Kritiske constraints

### Swift strict concurrency + warnings-as-errors
`project.yml` sætter `SWIFT_STRICT_CONCURRENCY: complete` og `OTHER_SWIFT_FLAGS: -warnings-as-errors`. Selv små Sendable/actor-isolation-issues failer build'et. Ny kode der krydser actor-grænser skal være eksplicit `@MainActor` eller `Sendable`. Bridge-klasserne der wrapper non-Sendable CoreML-typer (`CanaryASRBridge`) bruger `@unchecked Sendable` med en serial DispatchQueue til at gate access.

### Sandbox er DEAKTIVERET
`ENABLE_APP_SANDBOX: NO` i `project.yml` fordi CGEventTap (hotkey + cursor injection) ikke virker i sandboxen. Dette betyder også: Mac App Store er ikke en mulighed. Distribution er via signed DMG.

### Stabil signing til TCC-permissions
`CODE_SIGN_IDENTITY` er pinned til Apple Development cert SHA1 (`9E6001BC0D64B78FD7E2A7B2BA6279A222A4EB5F`). TCC tied csreq til cert-identity, så permissions overlever rebuilds — men kun hvis cert er det samme. Hvis cert udløber: opdater hash via `security find-identity -v -p codesigning`. Dev'ere uden Apple Developer-konto: fjern `CODE_SIGN_IDENTITY` + `DEVELOPMENT_TEAM` linjerne for ad-hoc signing (permissions skal granté'es på ny ved hver rebuild).

### macOS 15+ deployment target
CanaryKit kræver macOS 15 (Sequoia). `deploymentTarget.macOS = "15.0"`. Apple Silicon kun — Intel-Macs falder tilbage til CPU og bliver ubrugelige (RTF ~5×).

### Permissions
Saga kræver **Microphone**, **Accessibility** (CGEventTap + cursor injection), **Speech Recognition** (wake-word + live-partial), **Reminders/Calendars** (EventKit), **Screen Recording** (vision-mode). Alle Info.plist-strings er på dansk. Wake-word + reminders/calendar er opt-in i Settings; mic + accessibility kræves ved første run.

### Dansk-dansk i kode + UI
Domæne-sprog er dansk. Kommentarer, log-strings, UI-tekster og test-navne er på dansk. Variabel- og type-navne er engelske. Følg den eksisterende stil — engelske kommentarer i nye filer er en stor stilbrud.

## Tests

Tests er skrevet i Swift Testing framework (ikke XCTest) — `import Testing` + `@Test` + `#expect`. Test-target er `SagaCoreTests`, tester mod hovedappen via `@testable import Saga`. Coverage er aktiveret (`gatherCoverageData: true`).

CoreML-modellerne loades IKKE i tests — fokus er på pure logik (vocabulary, filler-strip, snippet-expansion, mode-trigger-matching, sentence-flusher, VAD, keychain). Integration-tests af recording-pipeline er manuelle — se [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md).

## Roadmap & state

`docs/ROADMAP.md` er **single source of truth** for "hvor er vi" — den har en "Nuværende state"-sektion øverst og per-fase check-box-lister med commit-hashes. Læs den før du starter på en ny milestone.

Versions-bumps: ret `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` i `saga-app/project.yml`. `build-dmg.sh` trækker versionen derfra automatisk.
