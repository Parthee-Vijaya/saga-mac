# Saga

Mac-native voice assistant til dansk dictation og AI-modes — inspireret af Emma,
men kører Hviske v5.3 lokalt og bruger LM Studio til mode-LLM.

> **Status:** M0 (scaffold). Se [docs/ROADMAP.md](docs/ROADMAP.md).

## Hvordan virker den

Hold `Fn`-tasten → tal dansk → tekst indsættes ved cursor.

Sig "Hey Saga, oversæt det til engelsk" → Saga transcriberer, sender til lokal
LLM, og skriver svaret tilbage.

Alt kører lokalt: Hviske (ASR) på Apple Silicon via PyTorch+MPS, og din egen
LM Studio til LLM-modes.

## Arkitektur

```
Saga.app (Swift)  ──HTTP──→  saga-sidecar (Python+MPS, Hviske v5.3)
                  ──HTTP──→  LM Studio (localhost:1234, gemma-4-26b)
```

Se [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Krav

- macOS 14+ (Tahoe-fri test på 26.x)
- Apple Silicon (M1+) — PyTorch MPS er meget langsommere end CUDA, så pre-M1 er upraktisk
- Xcode 16+ med Swift 6.2
- `xcodegen` (`brew install xcodegen`)
- `uv` (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- LM Studio kørende på `localhost:1234` (eller skift i Settings)
- ~12 GB ledig disk (Hviske model 4-8 GB + dependencies)

## Setup

```bash
# 1. Klon
git clone git@github.com:Parthee-Vijaya/saga.git
cd saga

# 2. Setup Python sidecar + download model
./scripts/setup.sh

# 3. Generér Xcode-projekt
cd saga-app && xcodegen generate && open SagaApp.xcodeproj

# 4. Byg & kør i Xcode (Cmd+R)
#    Ved første kørsel granté: Mikrofon, Accessibility, (senere) Skærmoptagelse
```

## Faser

| Fase | Status |
|------|--------|
| M0 — scaffold | 🟢 done |
| M1 — dictation pipeline | ⚪ next |
| M2 — LM Studio modes | ⚪ |
| M3 — Hey Saga + reminders | ⚪ |
| M4 — vision | ⚪ |
| M5 — document analysis | ⚪ |
| M6 — custom modes | ⚪ |
| M7 — integrations | ⚪ |
| M8 — distribution | ⚪ |

## Licenser

- **Saga**: privat. Personlig brug.
- **Hviske v5.3** (syvai/hviske-v5.3): CC BY-NC 4.0 — ikke-kommerciel. Saga
  bundler ikke modellen; brugeren downloader den selv via Hugging Face.
- **PyTorch, FastAPI, Transformers, libsndfile**: respektive open-source-licenser.
