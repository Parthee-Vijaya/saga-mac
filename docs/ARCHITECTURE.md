# Saga — Arkitektur

## Overblik

Saga er en macOS status bar app der orkestrerer to lokale services:

1. **saga-sidecar** — Python FastAPI process der kører Hviske v5.3 (ASR) på
   PyTorch + MPS. Spawnes af Saga ved app-launch og dræbes ved app-quit.
2. **LM Studio** — Brugerens egen LM Studio-instans på `localhost:1234` der
   kører en stor LLM (default: gemma-4-26b). Saga starter den ikke; brugeren
   forventes at have LM Studio kørende.

Saga.app selv er en Swift/SwiftUI status bar app uden dock-icon
(`LSUIElement = true`). Alt UI lever i status bar dropdown + flydende HUDs +
en Settings-sheet.

## Modul-diagram

```
┌──────────────────────────── Saga.app ────────────────────────────────┐
│                                                                       │
│   ┌─────────────────────┐     ┌──────────────────────┐               │
│   │ MenubarController   │     │ SettingsView         │               │
│   │ (status bar icon)   │     │ (preferences sheet)  │               │
│   └──────────┬──────────┘     └──────────┬───────────┘               │
│              │                            │                           │
│              └────────────┬───────────────┘                           │
│                           ▼                                           │
│              ┌────────────────────────┐                               │
│              │  SagaController         │                               │
│              │  (top-level orchestrator)│                              │
│              └─────────────┬──────────┘                               │
│                            │                                          │
│         ┌──────────────────┼─────────────────────────┐                │
│         ▼                  ▼                         ▼                │
│  ┌─────────────┐    ┌──────────────┐         ┌────────────┐          │
│  │ HotkeyManager│    │ AudioCapture │         │ ModeRouter │          │
│  │ (CGEventTap) │    │ (AVAudioEng) │         │            │          │
│  └──────┬──────┘    └──────┬───────┘         └─────┬──────┘          │
│         │                   │                       │                  │
│         │                   ▼                       ▼                  │
│         │            ┌─────────────┐         ┌────────────────┐       │
│         │            │ HviskeBridge│         │ LMStudioBridge │       │
│         │            │ (HTTP→7861) │         │ (HTTP→1234)    │       │
│         │            └─────┬───────┘         └────────┬───────┘       │
│         │                  │                          │                │
│         │                  ▼                          ▼                │
│         │           ┌──────────────────────────────────┐              │
│         │           │ CursorInjector (CGEvent typing)  │              │
│         │           └──────────────────────────────────┘              │
│         │                                                              │
│         ▼                                                              │
│  ┌──────────────┐                                                     │
│  │RecordingHUD  │  (overlay window, vises ved aktiv hotkey)           │
│  └──────────────┘                                                     │
└──────────────────────────────────────────────────────────────────────┘
            │                                       │
            ▼                                       ▼
┌───────────────────────────┐         ┌───────────────────────────┐
│ saga-sidecar (Python)     │         │ LM Studio (eksisterende)  │
│                           │         │                           │
│ FastAPI / uvicorn         │         │ OpenAI-kompatibel HTTP    │
│ PyTorch + MPS backend     │         │ /v1/chat/completions      │
│ Hviske v5.3 (Conformer 2B)│         │ gemma-4-26b-a4b           │
│                           │         │                           │
│ POST /transcribe          │         │                           │
│   audio (PCM 16kHz mono)  │         │                           │
│   → { text: "..." }       │         │                           │
└───────────────────────────┘         └───────────────────────────┘
```

## Kerneflows

### Flow 1 — Dictation (M1)

```
1. Bruger holder Fn nede → HotkeyManager fanger via CGEventTap
2. SagaController.startRecording():
   - AudioCapture starter (AVAudioEngine, 16kHz mono PCM, ringbuffer)
   - RecordingHUD vises
3. Bruger taler
4. Bruger slipper Fn → SagaController.stopRecording():
   - AudioCapture afsluttes, returnerer PCM-buffer
   - HviskeBridge.transcribe(pcm) — POST til sidecar
   - Sidecar returnerer { text: "..." }
   - CursorInjector.type(text) — CGEvent unicode keyboard events
5. RecordingHUD lukker
```

### Flow 2 — Mode-routing (M2)

```
1. Som Flow 1, men HviskeBridge returnerer "oversæt til engelsk: hej verden"
2. ModeRouter parser:
   - Trigger: "oversæt til engelsk"
   - Mode: TranslateMode(target: "en")
   - Payload: "hej verden"
3. ModeRouter beder LMStudioBridge om at kalde gemma med:
   - System: TranslateMode.systemPrompt
   - User: payload
4. LM Studio returnerer "Hello world"
5. CursorInjector.type("Hello world")
```

### Flow 3 — Hey Saga + Reminder (M3)

```
1. Mikrofonen lytter konstant (med VAD eller wake-word) [TODO: research]
2. "Hey Saga, mind mig om at ringe til Lars i morgen kl 14"
3. HviskeBridge transcriberer
4. ModeRouter detekterer "mind mig om" → ReminderMode
5. LMStudioBridge med ReminderMode.systemPrompt:
   - Output: { trigger: "2026-05-05T14:00", title: "Ring til Lars" }
6. ReminderEngine planlægger via UNUserNotificationCenter
7. Voice-confirm tilbage til brugeren via TTS [TODO: AVSpeechSynthesizer]
```

## Process-livscyklus

- **App-start:** `SidecarLauncher` spawner Python-processen via `Process()` med
  `uv run uvicorn ...`. Venter på `/health` at returnere 200. Timeout: 60 sek
  (første kørsel kan være langsom hvis model loades cold).
- **Ved transcribe:** `HviskeBridge` POST'er til localhost:7861. Hvis port ikke
  svarer → markér sidecar som dead, vis brugeren en notifikation.
- **App-quit:** `SidecarLauncher.shutdown()` sender SIGTERM, venter 5 sek, så
  SIGKILL hvis nødvendigt.
- **Crash recovery:** Hvis sidecar dør mens app'en kører, restart automatisk
  med exponential backoff (max 3 forsøg, så fail åbent).

## Permissions-flow

Ved første kørsel beder Saga om:

1. **Mikrofon** — `AVCaptureDevice.requestAccess(.audio)`. Info.plist:
   `NSMicrophoneUsageDescription`.
2. **Accessibility** — kræves for både CGEventTap (hotkey) og CGEvent typing
   (cursor inject). Saga åbner System Settings → Privacy → Accessibility, og
   beder brugeren toggle Saga ON. Verificeres via `AXIsProcessTrusted()`.
3. **Screen Recording** (M4 vision) — `CGRequestScreenCaptureAccess()`.

## Konfiguration

Settings gemmes i `UserDefaults.standard` (suite: `dk.parthee.saga`):

- `hviskeSidecarPort` — default: random ledig fra 7800-7899
- `lmStudioBaseURL` — default: `http://localhost:1234/v1`
- `lmStudioModel` — default: `gemma-4-26b-a4b`
- `hotkeyKeycode` — default: `Fn` (kCGEventFlagMaskSecondaryFn)
- `customModes` — JSON-array af user-defined modes
- `enabledModes` — set af mode-id'er
- `recordingHUDVisible` — bool

## Sikkerhed & privacy

- **Ingen telemetri**, ingen ekstern netværkstrafik undtagen til localhost.
- **Audio cachet kun i RAM** under transcription. Ingen disk-skrivning.
- **Transcripts** logges ikke som default. Hvis history-pane aktiveres (M3+),
  gemmes lokalt i `~/Library/Application Support/Saga/history.sqlite`.
- **API-nøgler** (hvis OpenAI tilføjes som backup) gemmes i Keychain via
  `kSecClassGenericPassword`.

## Test-strategi

- **SagaCore unit-tests** — Swift Testing (`@Test` macros). Mock-able bridges,
  test ModeRouter parsing, HotkeyManager state-machine.
- **Sidecar pytest** — test Hviske wrapper, audio resampling, FastAPI-routes.
- **End-to-end** — manuel test plan i `docs/TESTING.md` med
  reference-audio-clips og forventede transcripts.

## Bundling (M8)

- Embed Python-runtime via `python-build-standalone` (Astral) → ingen system-
  Python-afhængighed.
- `Saga.app/Contents/Resources/sidecar/` indeholder Python + venv.
- `SidecarLauncher` bruger embedded path frem for system `uv` ved produktion.
- Code-sign + notarize hele bundle. Auto-update via Sparkle.
