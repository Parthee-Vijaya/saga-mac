# saga-sidecar

Python FastAPI sidecar der kører Hviske v5.3 (dansk ASR) for Saga.app.

Spawnes typisk af Saga.app via `Process()`, men kan også køres standalone til debugging.

## Setup

```bash
# Kræver uv (https://docs.astral.sh/uv/)
uv sync

# Download Hviske-modellen til ~/.cache/huggingface (4-8 GB første gang)
uv run saga-download
```

## Kør server

```bash
# Default: localhost:7861
uv run saga-sidecar

# Custom port
uv run saga-sidecar --port 7900

# Debug mode (auto-reload, mere logging)
SAGA_DEBUG=1 uv run saga-sidecar
```

## API

### `GET /health`
Returnerer `{ "status": "ready" | "loading" | "error", "device": "mps" | "cpu", ... }`.

### `POST /transcribe`
Multipart upload:
- `audio`: WAV/PCM-bytes (16kHz mono foretrukket; ellers resamples)
- `language` (optional, default `da`)

Response:
```json
{
  "text": "Transkriberet tekst her",
  "duration_ms": 4123,
  "inference_ms": 412,
  "rtf": 0.10
}
```

## Hardware

- **Apple Silicon (M1+):** PyTorch MPS-backend. Forventet RTF ~0.3-0.6 på M2 Pro
  (langsommere end CUDA RTX 3090's ~0.002, men acceptabelt for hold-to-dictate).
- **Intel Mac:** CPU fallback. Meget langsom (~5-10× real-time). Ikke anbefalet.
- **CUDA-server:** Hvis du senere vil køre sidecar remote på en Linux-box med
  GPU, sæt `SAGA_DEVICE=cuda` og deploy.

## Licens

Hviske v5.3 er CC BY-NC 4.0 (ikke-kommerciel). Sidecar-koden selv er
proprietær (privat projekt). Se `../LICENSE`.
