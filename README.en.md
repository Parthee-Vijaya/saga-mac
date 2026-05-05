# Saga

Mac-native voice assistant for Danish dictation and AI modes.

**Hold `⌥` Right Option → speak Danish → text appears at the cursor.**

> 🇩🇰 [Læs på dansk](README.md)

> **LM Studio is NOT required** for ordinary use. Saga's dictation feature
> (push-to-talk → Danish text at cursor) runs entirely locally on Apple Silicon.
> LM Studio is only an **optional add-on** for AI modes (translate, summarize, format).

## Status

- ✅ **M0–M6 + M8** merged. Two releases published: v0.1.0 and v0.2.0.
- ⏸ **M7 (integrations)** intentionally skipped.
- 🛠 Next: see [docs/ROADMAP.md](docs/ROADMAP.md) and the public improvement plan.

## What works today

- ✅ Hold-to-talk hotkey (Right Option; configurable to Left Option, Right Cmd, Right Ctrl, Fn)
- ✅ Audio capture via `AVAudioRecorder` — robust on built-in mic, AirPods, USB
- ✅ Live waveform HUD with timer
- ✅ Danish speech-to-text via NVIDIA Canary-1b-v2 (CoreML / ANE) — RTF ~0.14 after warmup
- ✅ Cursor-text insertion in any app (TextEdit, Notes, browser, Claude Code, Slack, …)
- ✅ Status-bar app with live health indicators, transcript history, search
- ✅ Persistent transcript history (`~/Library/Application Support/Saga/history.json`, max 100 entries)
- ✅ LM Studio modes: translate, format, summarize, vibe-code, LinkedIn (M2)
- ✅ Voice reminders triggered by "remind me to …" / "mind mig om …" (M3)
- ✅ Wake word: "Hej Saga" / "Hey Saga" / "Okay Saga" (M3.B, off by default)
- ✅ Vision mode: "what do I see" → screen capture sent to vision-capable LM Studio model (M4)
- ✅ Document analysis: PDF/DOCX/RTF/TXT scanned for hidden clauses with severity grouping (M5)
- ✅ Stenograph mode: bypass all routing, raw transcription only (M6.0)
- ✅ Custom modes: user-defined modes with own triggers, prompts, temperature (M6)
- ✅ DMG distribution + first-run setup wizard (M8)
- ✅ Stable Apple Development signing — TCC permissions survive rebuilds

## Architecture

```
Saga.app (Swift 6, SwiftUI menubar app)
  ├─ AVAudioRecorder ────→ 16 kHz mono WAV          ┐
  ├─ CanaryKit (CoreML) ─→ ANE-accelerated ASR      ├─ Required (local)
  ├─ CursorInjector ─────→ CGEvent unicode typing   ┘
  ├─ ScreenCaptureKit ────→ vision frames           ┐
  ├─ PDFKit / NSAttribStr → document analysis       ├─ Optional (only used
  ├─ SFSpeechRecognizer ──→ wake-word detection     │  for advanced modes)
  └─ LM Studio (HTTP) ────→ local LLM @ :1234       ┘
```

ASR is **fully on-device** — no audio ever leaves the machine, no network connection
required for dictation. LM Studio is purely optional and is only used for mode
routing (translate, summarize, format, etc.).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the module diagram and
data flows.

## Hardware requirements

### For dictation only (Saga alone — *no* LM Studio required)

| | Minimum | Recommended |
|---|---|---|
| **Mac** | M1 (2020+) — requires Apple Neural Engine | M2 / M3 / M4 |
| **macOS** | 15.0 (Sequoia) | 26+ (Tahoe) |
| **RAM** | 8 GB | 16 GB |
| **Disk** | 2 GB free (Saga + Canary models) | 5 GB |

> ✅ That's **all** you need for Saga's dictation. You do **not** need to install
> LM Studio or anything else. Saga works offline.

### For LM Studio mode routing (optional)

| | Recommended |
|---|---|
| **RAM** | 24–32 GB (LM Studio + Saga + browser concurrently) |
| **Disk** | +16 GB (gemma-4-26b) or +5 GB (smaller models) |

LM Studio is a separate third-party app. Saga auto-detects it on `localhost`
but doesn't require it to function.

**Intel Macs are not supported** — Canary `mlpackage` files are compiled for
Apple Silicon and fall back to CPU on Intel, yielding RTF ~5× (unusable live).

## Installation (end users)

The latest signed DMG is available on
[GitHub Releases](https://github.com/Parthee-Vijaya/saga-mac/releases). Download,
mount, drag `Saga.app` to `/Applications`, then launch via Spotlight.

For step-by-step instructions including Gatekeeper notes, the first-run wizard,
and troubleshooting, see [docs/INSTALL.md](docs/INSTALL.md).

## Building from source

```bash
# Prerequisites
brew install xcodegen

# Clone this repo + canary-coreml as siblings
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/Parthee-Vijaya/saga-mac.git
git clone https://github.com/Parthee-Vijaya/canary-coreml.git

# Convert Canary-1b-v2 to CoreML (~5–10 min, see canary-coreml README)
cd canary-coreml/python
uv venv --python 3.11 .venv && source .venv/bin/activate
uv pip install -r requirements.txt
python 01_download.py
python 03_pytorch_to_coreml.py
python 03b_reexport_decoder_with_lmhead.py
python 06_export_preprocessor.py

# Generate + build Saga
cd ../../saga-mac/saga-app
xcodegen generate
open Saga.xcodeproj
# Cmd+R in Xcode. On first run: grant Microphone + Accessibility in System Settings.
```

For developers without an Apple Developer account, remove `CODE_SIGN_IDENTITY`
and `DEVELOPMENT_TEAM` from `saga-app/project.yml` — the app will be ad-hoc
signed (works, but permissions need re-granting on every rebuild).

### Building a DMG

```bash
./scripts/build-dmg.sh
# → dist/Saga-X.Y.Z.dmg
```

For notarized release builds, see [docs/RELEASE.md](docs/RELEASE.md).

## Usage

1. Launch Saga via Spotlight (`Cmd+Space → Saga`). The status-bar icon appears.
2. Place the cursor in any text field (Notes, Mail, Slack, Claude Code, …).
3. **Hold Right Option (`⌥`)** → speak Danish → release → text inserted.
4. Click the status-bar icon for live status, recent transcripts, and settings.
5. The History window supports search and copy-to-clipboard.

## Modes (M2)

When LM Studio is running, trigger phrases route output through a local model:

- `oversæt til engelsk: hej verden` → "Hello world"
- `opsummer: [long Danish text]` → 2-sentence TL;DR
- `linkedin: vi lancerede X` → polished LinkedIn post
- `kode: an API that fetches the weather` → English coding prompt

You can also create your own modes in **Settings → Custom modes** with your own
triggers, system prompts, and temperature.

## Privacy

- No audio leaves the machine (Canary runs locally)
- No telemetry, no analytics
- Transcripts are stored locally and can be cleared from the History window
- If LM Studio is configured: only the resulting prompts are sent to
  `localhost:1234` — never the audio

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions, code style, and
how to open a PR. Bug reports and feature requests via
[GitHub Issues](https://github.com/Parthee-Vijaya/saga-mac/issues). Security
issues: see [SECURITY.md](SECURITY.md).

## Licenses

- **Saga**: see [LICENSE](LICENSE). Currently "All Rights Reserved" — a formal
  open source license is being chosen. The repo is public for transparency.
- **Canary-1b-v2** (NVIDIA): CC BY 4.0 — free commercial use with attribution.
  The CoreML conversion lives in
  [canary-coreml](https://github.com/Parthee-Vijaya/canary-coreml).
- **CanaryKit** (Swift Package in canary-coreml): MIT.
- **PyTorch, CoreMLTools, Transformers, NeMo**: respective open-source licenses.

## Repository

https://github.com/Parthee-Vijaya/saga-mac
