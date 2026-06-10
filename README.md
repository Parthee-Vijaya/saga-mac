# Saga

[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-black?logo=apple)](https://support.apple.com/en-us/HT211814)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://www.swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Saga er en Mac-native voice-assistant der gør tale til tekst på dansk uden at sende noget til skyen.**

Du holder ⌥ Højre Option, taler dansk, og slipper. Teksten lander præcist hvor din cursor står — uanset om du er i Notes, Mail, Slack, Claude, VS Code eller en webformular i Chrome. Hele transkriptionen kører på din Mac via Apple Neural Engine. Ingen lyd forlader maskinen. Ingen abonnement. Ingen telemetri.

## ASR-engines (vælg i Settings → Voice)

| Engine | Sprog | License | Kvalitet (FLEURS-DA, strict) | Best til |
|---|---|---|---|---|
| **Canary-1b-v2** (default) | 25 EU-sprog inkl. dansk | Apache 2.0 (kommerciel-OK) | 11.39% WER | Multi-lingual, code-switching |
| **Hviske-v3** (opt-in) | Kun dansk | CC BY-NC 4.0 (privat) | 10.74% WER | Pure-dansk samtale |
| **Apple Speech** (fallback) | Tamilsk + andre | Apple SLA | varierer | Sprog Canary ikke dækker |

**Distribution i dag:** DMG'en (~1,7 GB) bundler Canary — dictation virker offline fra første launch. Hviske installeres separat via søsterprojektet [hviske-coreml](https://github.com/Parthee-Vijaya/hviske-coreml) (~2,9 GB) og aktiveres i Settings → Voice; Saga falder tilbage til Canary indtil modellen er på plads. Slim-DMG med on-demand-download er på roadmap (kræver hostede model-releases).

## Det den kan

**Dictation** — Tryk og tal. Saga bruger NVIDIA Canary-1b-v2 omkonverteret til CoreML for hurtig dansk transkription (under 200ms inference på en M-serie Mac). Plus 10 europæiske sprog samt **tamilsk** via Apple's on-device Speech-recognition.

**Live tekst i HUD** — Mens du taler ser du transkriptionen rulle live i et kompakt frosted-glass HUD nederst på skærmen. Du behøver ikke gætte hvad der bliver fanget.

**Wake-word + samtale-mode** — Sig *"Hej Saga"* eller *"Hej Jarvis"* og du er i en flydende dialog. Saga svarer i tale (Apple TTS eller ElevenLabs), viser captions med typewriter-effekt, og slutter når du siger *"tak"* eller *"farvel"*.

**Voice-edit** — Markér tekst i hvilken som helst app, hold ⇧+⌥, og dikter en instruktion: *"gør det mere formelt"*, *"skriv det som en email"*, *"fix typos"*. Markeringen overskrives med det redigerede svar. Virker også i Electron-apps som Claude og Slack via clipboard-fallback.

**Inline AI-kommandoer** — Sig fx *"...skriv det som en formel email"* mens du dikterer, så omformulerer Saga indholdet inline.

**Modes** — Trigger-baserede transformationer: *oversæt til engelsk*, *opsummer*, *formatér*, *vibecode*, *linkedin*, *vision* (analysér skærm).

**Apple-økosystem** — Sig *"mind mig om at ringe til mor i morgen kl 14"* → ny reminder i Apple Reminders synket til iPhone + Watch via iCloud. Sig *"book møde med Lars i morgen kl 14 til 15 om Q3"* → ny event i Apple Kalender. Begge via EventKit, ingen cloud, ingen tredjepart.

**Robust intent-detection** — Hvis Canary mishører trigger-fraser ("mind mig om" → "Det regnede" på dansk er almindeligt), klassificerer en lokal LLM intentionen baseret på tids- og handlings-keywords i transcripten — så reminders + kalender-aftaler havner det rigtige sted selv ved upræcis ASR.

**Custom modes med multi-shot examples** — Lav dine egne modes med trigger-fraser, system-prompts og **few-shot examples** (input/output-par der gives LLM som eksempler). Markant bedre konsistens for tricky modes som "konverter til formel email" eller "lav til bullet-points". Plus **live-test**: validér promptet mod LM Studio mens du tweaker uden at lukke editoren.

**Per-app profiler med hurtig-opsætning** — Bind specifikke modes til specifikke apps: altid format-mode i Notes, altid stenograf i Slack/Claude, altid tamilsk i WhatsApp. **14 pre-defined apps** (Mail, Outlook, Notes, Pages, Word, Slack, Discord, Beskeder, WhatsApp, Xcode, VS Code, Cursor, Claude, LinkedIn) klar til ét-klik-aktivering.

**Voice snippets** — Trigger → tekstblok-erstatninger. Sig *"hilsen"* → "Med venlig hilsen, [dit navn]\n[din email]" indsættes som multi-line-blok. Editor i Settings. **Valgfri iCloud Drive-sync** så snippet-bibliotek er det samme på work-Mac og home-Mac.

**Daily voice-journal** — Saga akkumulerer alle dictations i markdown-fil per dag i `~/Saga-journal/YYYY-MM-DD.md` med timestamps. Refleksiv journaling uden at skifte værktøj.

**Privacy-mode** — Toggle der suspenderer al history-logging midlertidigt. Aktiv: shield-ikon i menubar, ingen entries i history, ingen stats-opdatering, ingen journal-skrivning. Slukker ved app-genstart.

**Smart Electron-app-injection** — Saga detekterer Claude, Slack, VS Code, Discord, Notion m.fl. og bruger paste-strategi fra start (clipboard+⌘V) i stedet for unicode-keyboard. Fjerner ~80ms latens i Electron-apps.

**Vocabulary + filler-strip** — Egen ordbog der retter ASR-fejl på dine egennavne og akronymer. Strip "øh", "altså", "ligesom" automatisk så dictation er ren ud-af-boksen.

**Document-analyse** — Træk en PDF/DOCX ind, og Saga finder bindings-perioder, fortrydelsesfrister og kritiske passager via LLM.

**Historik med fuld-tekst-søgning + filtre** — 100 seneste dictations gemt lokalt. Søg fri tekst, filtrér på dato (i dag/7 dage/30 dage) eller mode. Kopiér rå-transkript eller resultat med ét klik.

**Stenograf-mode** — Ren dictation uden LLM-routing — minimal latens når du bare vil have rå tekst.

## Hvorfor det er anderledes

**Fuldt lokalt.** Canary-modellen er bundlet med appen (1.7 GB) og kører på din Apple Neural Engine. Ingen audio-stream til Apple, OpenAI eller andre. For LLM-features (modes, voice-edit, samtaler) tilsluttes din egen lokale **LM Studio** — ingen API-keys, ingen rate-limits, ingen data der forlader maskinen.

**Privat by default.** Ingen telemetri, ingen analytics, ingen anonyme metrics. Din transkriptions-historik gemmes lokalt i `~/Library/Application Support/Saga/` og kan slettes når som helst.

**Ingen subscription.** Saga er privat-projekt-software. Du betaler nul kroner. Hvis du vil have ElevenLabs-stemmer i samtale-mode, er det en valgfri tilføjelse med din egen ElevenLabs-konto.

**Mac-native UI.** Dark-first design der ignorerer system-tema. Frosted-glass HUD med live waveform og auto-scrollende live transkript. Status-bar app uden dock-icon — den er der når du har brug for den, usynlig ellers.

## Hvad du får ud af det

- **Hurtigere skrivning** end at taste, særligt for dansk hvor andre dictation-værktøjer er flade.
- **Polerede tekster** i samme bevægelse — ingen separate kopier-til-ChatGPT-runder.
- **Komplet kontrol over data** — alt forlader aldrig din Mac.
- **Multi-sprog inklusiv tamilsk** — for tværsproget arbejde uden at skifte mellem værktøjer.
- **Ét hotkey, mange use-cases** — fra hurtig email-dictation til guided AI-redigering.

Saga er for personer der gerne vil have produktivt voice-input på dansk, men ikke vil binde sig til cloud-tjenester, betalte abonnementer eller usikre data-flows.

---

> **Status — v0.9.0 ship'et** ([release](https://github.com/Parthee-Vijaya/saga-mac/releases/tag/v0.9.0)):
> menubar-redesign (Living Glass + Command Surface tiles), dual ASR-engine
> (Canary default + Hviske opt-in), license-disclosure, saga-cli, benchmarks.
>
> **Tidligere sprints (alle i main):**
>
> **Sprint 1:** Voice snippets, privacy-mode (no
> history), Daily voice-journal, smart Electron-detection, multi-monitor
> HUD-positionering.
>
> **v0.10.0 (Sprint 2 — Apple-økosystem, ikke tagget endnu):** Apple
> Reminders + Apple Calendar via EventKit (synker til iPhone+Watch),
> LLM intent-classifier som fallback når Canary mishør triggers,
> eksplicit "Puttet reminder/kalender"-confirmation, default-model
> skiftet til gpt-oss-20b (hurtigere reasoning), 14 pre-defined
> app-profile-presets, snippet iCloud Drive-sync.
>
> **v0.11.0 (Sprint 3 — AI/UX polish, ikke tagget endnu):** Custom mode
> live-test (test prompts mens du tweaker), Companion typewriter-effekt
> (seneste 20 chars i accent-farve), multi-shot prompt-templates med
> few-shot examples, history dato + mode-filter.
>
> Se [docs/ROADMAP.md](docs/ROADMAP.md) for fuld faseliste.

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
- ✅ Oversæt / Format / Opsummer / Vibecode / LinkedIn / Vision
- ✅ Document-analyse — drop PDF/DOCX i HUD'et → flag binding-perioder, fortrydelses-frister
- ✅ Custom modes editor i Settings (egne triggers + system-prompts + temperatur)
- ✅ **Multi-shot examples** i custom modes — input/output-par for bedre konsistens
- ✅ **Live-test** i editor — kør test mod LM Studio mens du tweaker prompten
- ✅ Per-app profiler med **14 pre-defined presets** (Mail, Slack, Xcode, …)
- ✅ Model-picker — skift hurtigt mellem alle modeller fundet i LM Studio
- ✅ **LLM intent-classifier** — fallback når Canary mishør triggers (Canary's "Det regnede" → reminder routes korrekt)
- ✅ Default-model `openai/gpt-oss-20b` (hurtigere reasoning end gemma-4-26b)

**Apple-økosystem-integration (EventKit):**
- ✅ **Apple Reminders** — sig "mind mig om at ringe til mor i morgen kl 14" → reminder synket til iPhone + Watch via iCloud
- ✅ **Apple Kalender** — sig "book møde med Lars i morgen kl 14 til 15 om Q3" → ny event i kalenderen
- ✅ Permission-flow med graceful fallback til lokal notification hvis EventKit denied
- ✅ Default-list/-calendar picker i Settings → Reminders & Kalender
- ✅ Eksplicit confirmation: "✓ Puttet reminder i Apple Reminders: …"

**Snippets, journal, privacy (Sprint 1):**
- ✅ **Voice snippets** — trigger → multi-line tekstblok (fx "hilsen" → email-signatur)
- ✅ Snippet **iCloud Drive-sync** — same library på tværs af Macs
- ✅ **Daily voice-journal** — alle dictations samlet i markdown per dag (~/Saga-journal/)
- ✅ **Privacy-mode** — shield-ikon, ingen history/stats/journal logging når aktiv
- ✅ Smart **Electron-app-detection** — paste-from-start i Claude/Slack/VS Code/Notion m.fl.

**Wake-word + Companion:**
- ✅ "Saga" eller "Jarvis" som wake-word (on-device SFSpeechRecognizer)
- ✅ Companion-conversation: efter wake-word → flydende dialog med live caption-overlay
- ✅ **Typewriter-effekt** på captions — seneste 20 chars vises i accent-farve mens resten er primary
- ✅ TTS svar via Apple AVSpeechSynthesizer eller ElevenLabs (valgfrit)
- ✅ Auto-end ved "tak" / "farvel" / "stop"
- ✅ Cursor-bubble — lille pulserende prik under cursor mens Saga lytter

**System:**
- ✅ Status-bar app med live health-status, transkriberings-historik og søgning
- ✅ Persistent transkript-historik (`~/Library/Application Support/Saga/history.json`, max 100 entries)
- ✅ **Historik-vindue med fuld-tekst-søgning + filtre** — dato (i dag/7/30 dage) + mode-picker
- ✅ Multi-monitor-aware HUD — vises på den skærm hvor cursor er
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
| **v0.8.0** | Stats-tab (ord/tegn/lyd-tid/RTF), HUD-polish v2 (audio-reactive accent, idle breathing, word-by-word highlight, gradient fade), Odin-mode (RAG-vidensbase) | ✅ done |
| **Sprint 1 (v0.9.0)** | Voice snippets, privacy-mode, daily voice-journal, Electron-app-detection, multi-monitor HUD | ✅ done |
| **Sprint 2 (v0.10.0)** | Apple Reminders + Calendar via EventKit, intent-classifier (LLM-fallback), 14 app-presets, snippet iCloud-sync, eksplicit confirmation | ✅ done (ikke tagget) |
| **Sprint 3 (v0.11.0)** | Custom mode live-test, multi-shot prompt-templates (few-shot examples), Companion typewriter-effekt, history dato/mode-filter | ✅ done (ikke tagget) |
| **M7** | Webhook-integrations (n8n/Sheets) | ⏸ skipped per ønske |
| **Sideprojekt** | hviske-coreml — Hviske → CoreML for bedre dansk-WER | ⚪ ~10 dage |

## Arkitektur

```
Saga.app (Swift 6, SwiftUI status bar)
  ├─ AVAudioRecorder ────→ 16 kHz mono WAV          ┐
  ├─ CanaryKit (CoreML) ─→ ANE-accelereret ASR      │
  ├─ CursorInjector ────→ CGEvent unicode typing    ├─ Påkrævet (lokalt)
  ├─ EventKit ──────────→ Apple Reminders/Kalender  │
  ├─ iCloud Drive (fil) ─→ snippet-sync valgfrit    ┘
  └─ LM Studio (HTTP) ──→ valgfri mode-LLM           ─ Valgfri (kun til modes)
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
gh release download v0.9.0 --repo Parthee-Vijaya/saga-mac --pattern "Saga-*.dmg"
open Saga-0.9.0.dmg
```

**Med `curl` + Personal Access Token:**

```bash
# Lav en GitHub PAT med 'repo'-scope: https://github.com/settings/tokens
export GH_TOKEN="ghp_din_token_her"

# Find asset-id'et
ASSET_ID=$(curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/tags/v0.9.0" \
  | grep '"id"' | head -2 | tail -1 | grep -oE '[0-9]+')

# Hent DMG (følg redirect til S3)
curl -L -o Saga-0.9.0.dmg \
  -H "Authorization: token $GH_TOKEN" \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/Parthee-Vijaya/saga-mac/releases/assets/$ASSET_ID"

open Saga-0.9.0.dmg
```

### Eller via browser

Hent fra [GitHub Releases](https://github.com/Parthee-Vijaya/saga-mac/releases/tag/v0.9.0) →
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

> ⚠️ **Saga kan IKKE bygges alene.** `saga-app/project.yml` har en lokal
> SPM-dependency på søsterrepoet `canary-coreml` (forventes på
> `../../canary-coreml/swift` relativt til `saga-app/`). Klon begge repos
> side-om-side som vist nedenfor, ellers fejler `xcodegen`-projektet med
> "Missing package product 'CanaryKit'".

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

## Localization

Saga er **dansk-first by design** — det meste af UI'et er stadig hardcoded i dansk. Localization-infrastrukturen er klar (`saga-app/Resources/da.lproj/` og `en.lproj/`), så community-bidrag af engelske, svenske, norske eller tyske oversættelser er meget velkomne. Se [CONTRIBUTING.md](CONTRIBUTING.md) for hvordan.

## Bidrage

Saga er et åbent projekt — bug-rapporter, feature-forslag og pull requests er velkomne.

- **Bugs/forslag**: [open en issue](https://github.com/Parthee-Vijaya/saga-mac/issues/new/choose)
- **Pull requests**: læs [CONTRIBUTING.md](CONTRIBUTING.md) for build-guide, kode-stil og PR-checklist
- **Sårbarheder**: se [SECURITY.md](SECURITY.md)
- **Adfærdskodeks**: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) (Contributor Covenant 2.1)

## Licenser

| Komponent | Licens | Note |
|---|---|---|
| **Saga** (denne kode) | [MIT](LICENSE) | Bruges frit, inkl. kommercielt |
| **Canary-1b-v2** (NVIDIA, default ASR) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Kommerciel-OK med attribution |
| **CanaryKit** Swift Package | [MIT](https://github.com/Parthee-Vijaya/canary-coreml) | Wrapper-kode i søsterprojektet |
| **Hviske-v3** (syv.ai, opt-in ASR) | [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) | **Kun ikke-kommerciel brug** — accepteres via in-app modal før download |
| **WhisperKit** (Argmax) | MIT | Bruges internt til Hviske-inference |
| **Sparkle** | MIT | Auto-update |
| **Apple Speech.framework** | Apple SLA | Indbygget i macOS |

Når du vælger Hviske som engine i Settings, viser Saga en modal med CC BY-NC 4.0-betingelserne. Du kan altid skifte tilbage til Canary i Settings → Voice.

## Repo

Public: https://github.com/Parthee-Vijaya/saga-mac
