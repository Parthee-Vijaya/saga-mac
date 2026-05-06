# Saga

Mac-native voice assistant til dansk dictation og AI-modes.

**Hold `⌥` Højre Option → tal dansk → tekst indsættes ved cursor.**

> **LM Studio er IKKE nødvendig** for almindelig brug. Saga's dictation-funktion
> (push-to-talk → dansk tekst ved cursor) kører fuldt lokalt på Apple Silicon.
> LM Studio er kun en **valgfri tilføjelse** for AI-modes (oversæt, opsummer, formatér,
> voice-edit, Companion-samtaler).

> **Status v0.6.0** — Superwhisper-inspireret design-redesign: kompakt HUD med
> hvid waveform + rød REC-indikator + keyboard-pills, dark-first UI på alle
> flader, single-step guided wizard, ny omvendt trekant som app-icon. Plus
> alle v0.5.0-features. Se [docs/ROADMAP.md](docs/ROADMAP.md) for fuld faseliste.

## Hvad virker lige nu (verificeret)

**Dictation + cursor-injection (kerne):**
- ✅ Hold-til-tal hotkey (Højre Option, virker på Apple-keyboard og Logitech MX-serien)
- ✅ Audio capture via AVAudioRecorder — robust på Built-in mic, AirPods, USB
- ✅ Live waveform-HUD med tidstæller under recording
- ✅ Dansk speech-to-text via NVIDIA Canary-1b-v2 (CoreML/ANE) — RTF ~0.14 efter warmup
- ✅ Tekst inserted ved cursor i hvilken som helst app (TextEdit, Notes, browser, Slack, …)
- ✅ VAD auto-stop — Saga stopper selv ved stilhed, ingen hold-til-tale nødvendig (toggle i Settings)
- ✅ Vocabulary post-processor — egen ordbog der retter ASR-fejl (Settings → Ordforråd)
- ✅ Stenograf-mode — ren dictation, ingen LLM-routing

**Voice-edit (Shift+⌥):**
- ✅ Markér tekst i hvilken som helst app, hold ⇧+⌥, tal instruktion → markeringen overskrives
- ✅ Virker i Electron-apps (Claude, Slack, VSCode, Notion) via clipboard-fallback
- ✅ Genaktiverer original app før paste — kan tjekke LM Studio under tænkning uden at miste fokus

**Modes (kræver LM Studio):**
- ✅ Oversæt / Format / Opsummer / Vibecode / LinkedIn / Reminder / Vision
- ✅ Document-analyse — drop PDF/DOCX i HUD'et → flag binding-perioder, fortrydelses-frister
- ✅ Custom modes editor i Settings (egne triggers + system-prompts + temperatur)
- ✅ Per-app profiler — fx forced "format"-mode i Notes, stenograf i Mail
- ✅ Model-picker — skift hurtigt mellem alle modeller fundet i LM Studio

**Wake-word + Companion:**
- ✅ "Saga" eller "Jarvis" som wake-word (on-device SFSpeechRecognizer)
- ✅ Companion-conversation: efter wake-word → flydende dialog med live caption-overlay
- ✅ TTS svar via Apple AVSpeechSynthesizer eller ElevenLabs (valgfrit)
- ✅ Auto-end ved "tak" / "farvel" / "stop"
- ✅ Cursor-bubble — lille pulserende prik under cursor mens Saga lytter

**System:**
- ✅ Status-bar app med live health-status, transkriberings-historik og søgning
- ✅ Persistent transkript-historik (`~/Library/Application Support/Saga/history.json`, max 100 entries)
- ✅ Stabil Apple Development signing — TCC-permissions overlever rebuilds
- ✅ Slim-DMG — Canary-modeller downloades ved første start (sparer plads i DMG)
- ✅ First-run wizard — onboarding med permission-flow

## Roadmap

| Fase | Beskrivelse | Status |
|---|---|---|
| **M0–M0.G** | Scaffold, ASR-pivot til Canary, AVAudioRecorder, signing, waveform-HUD | ✅ done |
| **M1** | Dictation-pipeline end-to-end | ✅ done |
| **M2** | LM Studio modes (oversæt/format/opsummer/vibecode/linkedin) | ✅ done |
| **M3** | Voice-reminders | ✅ done |
| **M3.B** | Wake-word "Hej Saga" via SFSpeechRecognizer | ✅ done |
| **M4** | Vision (multi-modal LLM screen-capture) | ✅ done |
| **M5** | Document-analyse (PDF/DOCX flagging) | ✅ done |
| **M6** | Custom modes editor | ✅ done |
| **M6.0** | Stenograf-mode toggle | ✅ done |
| **M7** | Integrations (n8n/Kalender/Sheets) | ⏸ skipped per ønske |
| **M8** | DMG distribution + notarization-scaffolding | ✅ done |
| **CLI-sprint** | TTS (Apple+ElevenLabs), Companion conversation, settings-split, cursor-bubble, live-partial, per-app profiles | ✅ done |
| **Sprint B** | Vocabulary post-processor, VAD auto-stop, voice-edit | ✅ done |
| **Voice-edit v2** | Shift+⌥ trigger, clipboard-fallback for Electron-apps, target-app re-aktivering, model-picker | ✅ done |
| **Design-redesign** | Superwhisper-inspireret dark-first UI, kompakt HUD med hvid waveform + rød REC, keyboard-pills, single-step guided wizard, ny app-icon (omvendt trekant) | ✅ done |
| **Sideprojekt** | hviske-coreml — Hviske → CoreML for bedre dansk-WER | ⚪ ~10 dage |

## Arkitektur

```
Saga.app (Swift 6, SwiftUI status bar)
  ├─ AVAudioRecorder ────→ 16 kHz mono WAV          ┐
  ├─ CanaryKit (CoreML) ─→ ANE-accelereret ASR      ├─ Påkrævet (lokalt)
  ├─ CursorInjector ────→ CGEvent unicode typing    ┘
  └─ LM Studio (HTTP) ──→ valgfri mode-LLM           ─ Valgfri (kun til M2-modes)
```

ASR kører fuldt **on-device** — ingen audio forlader maskinen, ingen netværksforbindelse
nødvendig. LM Studio er **kun valgfri** og bruges udelukkende hvis du vil have
mode-routing (oversæt/opsummer/formatér).

Se [docs/ROADMAP.md](docs/ROADMAP.md) for fuld faseliste + per-fase commit-hashes.

## Hardware-krav (Mac)

### Til almindelig dictation (Saga alene — *ingen* LM Studio krævet)

| | Minimum | Anbefalet |
|---|---|---|
| **Mac** | M1 (2020+) — kræver Apple Neural Engine | M2 / M3 / M4 |
| **macOS** | 15.0 (Sequoia) | 26+ (Tahoe) |
| **RAM** | 8 GB | 16 GB |
| **Disk** | 2 GB ledig (Saga + Canary-modeller) | 5 GB |

> ✅ Det er **alt** du behøver for at bruge Saga til dictation. Du behøver IKKE
> installere LM Studio eller noget andet. Saga virker offline.

### Hvis du senere vil have LM Studio mode-routing (M2 — kommer)

| | Anbefalet |
|---|---|
| **RAM** | 24-32 GB (LM Studio + Saga + browser samtidig) |
| **Disk** | +16 GB (gemma-4-26b) eller +5 GB (mindre modeller) |

LM Studio er en separat tredjeparts-app. Saga finder den automatisk hvis den
kører på localhost, men kræver intet for at virke.

Intel-Macs er ikke supporterede — Canary-mlpackages er kompileret til Apple Silicon
og falder tilbage til CPU på Intel, hvilket giver RTF ~5× (ubrugeligt live).

## Disk + RAM-forbrug konkret

### Saga + Canary (ASR)

| Komponent | Disk | RAM (kørende) |
|---|---|---|
| Saga.app (signed Debug-build) | ~12 MB | ~80 MB idle |
| `CanaryEncoder.mlpackage` (FP16) | 1.5 GB | i model-RAM |
| `CanaryDecoderLM.mlpackage` (FP16) | 291 MB | i model-RAM |
| `CanaryPreprocessor.mlpackage` | 1.2 MB | minimal |
| **Total Saga + Canary FP16** | **~1.8 GB** | **~3.6 GB peak (model loaded)** |
| Alternativ: int4-decoder | -218 MB | -200 MB |

Cold-start: 8-22 sek (CoreML JIT-kompilerer ANE-kerner). Warm-start: <1 sek.

### LM Studio (LLM, **valgfri** — kun til mode-routing i M2)

LM Studio er **ikke** nødvendig for at bruge Saga. Hop til afsnittet om
[Installation](#installation-slutbrugere) hvis du kun vil have dictation.

Saga's default model (kan ændres i Settings):

**`gemma-4-26b-a4b` (Q4_K_M-kvantiseret GGUF)**
- 26B total params, 4B aktive (Mixture of Experts)
- Disk: **~16 GB**
- RAM: **~18-20 GB** under inference
- Inference: ~30-60 tokens/sek på M-series

Hvis 16 GB RAM er stramt, kan du i stedet bruge:
- `gemma-2-9b-it-Q4_K_M` (~5 GB disk, ~7 GB RAM, lidt dårligere dansk)
- `llama-3.1-8b-instruct-Q4_K_M` (~5 GB disk, ~7 GB RAM, god generel)
- `qwen2.5-7b-instruct-Q4_K_M` (~4 GB disk, ~6 GB RAM)

LM Studio app fylder ~200 MB selv (separat installation fra `lmstudio.ai`).

### Total peak disk + RAM

|  | Disk | RAM |
|---|---|---|
| **Saga + Canary alene** (almindelig brug) | 1.8 GB | 3.6 GB |
| + LM Studio + gemma-4-26b (kun hvis du vil have modes) | 18 GB | 24 GB |
| **+ macOS + browsere kørende** | — | ~30 GB anbefalet |

## Installation (slutbrugere)

### Hurtig download via terminal

Repo'et er privat, så download kræver authentication. Vælg én af:

**Med `gh` CLI** (anbefalet — håndterer auth automatisk):

```bash
brew install gh
gh auth login
gh release download v0.6.0 --repo Parthee-Vijaya/saga-mac --pattern "Saga-*.dmg"
open Saga-0.6.0.dmg
```

**Med `curl` + Personal Access Token:**

```bash
# Lav en GitHub PAT med 'repo'-scope: https://github.com/settings/tokens
export GH_TOKEN="ghp_din_token_her"

# Find asset-id'et
ASSET_ID=$(curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/tags/v0.6.0" \
  | grep '"id"' | head -2 | tail -1 | grep -oE '[0-9]+')

# Hent DMG (følg redirect til S3)
curl -L -o Saga-0.6.0.dmg \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/assets/$ASSET_ID"

open Saga-0.6.0.dmg
```

### Eller via browser

Hent fra [GitHub Releases](https://github.com/Parthee-Vijaya/saga-mac/releases/tag/v0.6.0) →
træk Saga.app til Applications.

Se [docs/INSTALL.md](docs/INSTALL.md) for trin-for-trin guide inkl. Gatekeeper-bypass og
first-run wizard.

## Fortsætte udvikling fra en anden Mac

Saga's roadmap + state lever i [docs/ROADMAP.md](docs/ROADMAP.md) — det er
single-source-of-truth for "hvor er vi". Hver fase har en check-box-liste der
viser præcis hvad der er færdigt og hvad der mangler.

### Quick-start på ny Mac

```bash
# 1. Klon begge repoer side-om-side (Saga afhænger af canary-coreml)
mkdir -p ~/projekter && cd ~/projekter
git clone git@github.com:Parthee-Vijaya/saga-mac.git saga
git clone git@github.com:Parthee-Vijaya/canary-coreml.git

# 2. Tjek state
cd saga
cat docs/ROADMAP.md | head -40   # "Nuværende state"-section øverst
git log --oneline -10            # senest landed commits

# 3. Generér Xcode-projekt + byg
cd saga-app
brew install xcodegen
xcodegen generate
open SagaApp.xcodeproj
# Cmd+R for at bygge og køre. Permissions overlever fordi vi bruger
# stabil Apple Development signing — du skal ikke granté igen.
```

### Med Claude Code på den nye Mac

Hvis du kører Claude Code med samme `vidensbase/projekter/saga.md`-memory,
kan du sige **"load saga"** og den genoptager hvor sidste session slap.
Memory er per-Claude-installation, så hvis det er en frisk Claude:
peg den på dette repo + `docs/ROADMAP.md` → "Nuværende state"-sektion
giver hele kontekst i en mundfuld.

For en langtids-bevarende session-state, bruger Saga `docs/ROADMAP.md` som
canonical-state og `vidensbase/projekter/saga.md` (lokal memory) som
session-log med commit-hashes per fase.

## Setup (udviklere)

```bash
# Forudsætninger
brew install xcodegen
curl -LsSf https://astral.sh/uv/install.sh | sh

# Klon dette repo + canary-coreml ved siden af
cd ~/projekter
git clone git@github.com:Parthee-Vijaya/saga-mac.git saga
git clone git@github.com:Parthee-Vijaya/canary-coreml.git
cd canary-coreml/python && uv venv --python 3.11 .venv && source .venv/bin/activate
uv pip install -r requirements.txt

# Konvertér Canary-1b-v2 til CoreML (~5-10 min)
python 01_download.py
python 03_pytorch_to_coreml.py
python 03b_reexport_decoder_with_lmhead.py
python 06_export_preprocessor.py
python _export_tokenizer_json.py

# Generér + byg Saga
cd ../../saga/saga-app
xcodegen generate
open SagaApp.xcodeproj
# Cmd+R i Xcode. Ved første run: granté Mikrofon + Accessibility i System Settings.
```

For brugere uden Apple Developer-konto: fjern `CODE_SIGN_IDENTITY` og
`DEVELOPMENT_TEAM` linjerne i `saga-app/project.yml` — så bygger den ad-hoc
(virker, men permissions skal grantes på ny ved hver rebuild).

### Bygge DMG til distribution

```bash
./scripts/build-dmg.sh
# → dist/Saga-X.Y.Z.dmg (1.7 GB med mlpackages bundlet)
```

Test DMG'en på en frisk Mac vha. [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md).

## Brug

### Dictation (kerne)

1. Åbn Saga via Spotlight (`Cmd+Space → Saga`). Status-bar-ikon dukker op.
2. Sæt cursor i hvilket-som-helst tekstfelt (Notes, Mail, Slack, Claude Code, …)
3. **Hold Højre Option (`⌥`)** → tal dansk → slip → tekst indsættes
4. Klik status-bar-ikonet for live status, sidste 5 transkriptioner og indstillinger

### Voice-edit (⇧+⌥)

1. Markér tekst i hvilken som helst app (Notes, Mail, Claude, Slack, VSCode, Notion, …)
2. **Hold ⇧+⌥** → tal instruktion ("gør det mere formelt", "fix typos", "skriv som LinkedIn-post")
3. Slip → markeringen overskrives med det redigerede svar

Saga genaktiverer din originale app før indsætning, så du kan tjekke LM Studio's
progress under tænkning uden at miste fokus.

### Modes (kræver LM Studio)

Trigger-ord routes output gennem din lokale LM Studio:

- "oversæt til engelsk: hej verden" → "Hello world"
- "opsummer: [lang dansk tekst]" → 2-sætnings TL;DR
- "linkedin: vi annoncerede X" → polished LinkedIn-post
- "vibecode: en API der henter vejret" → engelsk prompt klar til Claude Code
- "vision: hvad ser jeg" → analyserer aktivt vindue
- "mind mig om at ringe til Mor i morgen kl 14" → opretter macOS-notifikation

### Wake-word + Companion

1. Aktivér i Settings → Stemme → "Aktivér 'Saga'/'Jarvis'"
2. Sig **"Hej Saga"** eller **"Hej Jarvis"** → Saga starter en samtale
3. Tal frit, Saga svarer via TTS med live caption-overlay
4. Sig **"tak"** / **"farvel"** / **"stop"** → samtalen slutter

## Privacy

- Ingen audio forlader maskinen (Canary kører lokalt)
- Ingen telemetri, ingen analytics
- Transkripter gemmes lokalt (kan slettes via "Ryd alt"-knap i historik)
- Hvis LM Studio er konfigureret: kun mode-prompts sendes til localhost:1234

## Licenser

- **Saga**: privat projekt, personlig brug.
- **Canary-1b-v2** (NVIDIA): CC BY 4.0 — fri commercial brug med attribution.
  CoreML-konvertering ligger i [canary-coreml-repo](https://github.com/Parthee-Vijaya/canary-coreml).
- **CanaryKit** (Swift Package i canary-coreml): MIT.
- **PyTorch, CoreMLTools, Transformers, NeMo**: respektive open-source-licenser.

## Repo

Privat: https://github.com/Parthee-Vijaya/saga-mac
