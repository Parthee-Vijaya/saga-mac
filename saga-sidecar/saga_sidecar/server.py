"""FastAPI server der eksponerer Hviske som transcription-endpoint."""

from __future__ import annotations

import argparse
import logging
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from .audio import decode_audio_bytes, decode_raw_pcm16
from .config import Config
from .hviske import HviskeASR

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("saga-sidecar")


class HealthResponse(BaseModel):
    status: str  # "ready" | "loading" | "error"
    device: str
    model_id: str
    version: str


class TranscribeResponse(BaseModel):
    text: str
    duration_ms: int
    inference_ms: int
    rtf: float


def make_app(config: Config) -> FastAPI:
    asr = HviskeASR(model_id=config.model_id, device=config.device)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        log.info("Starter Saga sidecar — model: %s, device: %s", config.model_id, asr.device)
        try:
            asr.load()
            asr.warmup()
            log.info("Sidecar klar på %s:%d", config.host, config.port)
        except Exception:
            log.exception("Kunne ikke loade Hviske — sidecar fortsætter, men /transcribe vil fejle")
        yield
        log.info("Sidecar lukker ned")

    app = FastAPI(title="Saga Sidecar", version="0.1.0", lifespan=lifespan)

    @app.get("/health", response_model=HealthResponse)
    async def health() -> HealthResponse:
        from . import __version__
        return HealthResponse(
            status="ready" if asr.is_loaded else "loading",
            device=asr.device,
            model_id=asr.model_id,
            version=__version__,
        )

    @app.post("/transcribe", response_model=TranscribeResponse)
    async def transcribe(
        audio: UploadFile = File(...),
        language: str = Form("da"),
        encoding: str = Form("auto"),  # "auto" | "pcm16" | "wav"
        sample_rate: int = Form(16_000),
    ) -> TranscribeResponse:
        if not asr.is_loaded:
            raise HTTPException(503, "Modellen er stadig under indlæsning, prøv igen om lidt")

        data = await audio.read()
        if not data:
            raise HTTPException(400, "Tom audio-payload")

        try:
            if encoding == "pcm16":
                samples = decode_raw_pcm16(data, sample_rate)
                sr = sample_rate
            else:
                samples, sr = decode_audio_bytes(data, target_sr=config.target_sample_rate)
        except Exception as e:
            raise HTTPException(400, f"Kunne ikke dekode audio: {e}") from e

        duration_s = len(samples) / sr
        if duration_s > config.max_audio_seconds:
            raise HTTPException(
                413,
                f"Audio er {duration_s:.1f}s — max {config.max_audio_seconds}s",
            )
        if duration_s < 0.1:
            raise HTTPException(400, "Audio er for kort (<0.1s)")

        try:
            result = asr.transcribe(samples, sample_rate=sr, num_beams=config.num_beams)
        except Exception as e:
            log.exception("Transcribe fejlede")
            raise HTTPException(500, f"Transcription-fejl: {e}") from e

        log.info(
            "transcribe ok: %.2fs audio → %dms inference (rtf=%.3f) tekst=%r",
            duration_s, result["inference_ms"], result["rtf"], result["text"][:80],
        )
        return TranscribeResponse(**result)

    return app


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Saga sidecar — Hviske v5.3 ASR server")
    p.add_argument("--host", default=None)
    p.add_argument("--port", type=int, default=None)
    p.add_argument("--device", choices=["auto", "mps", "cuda", "cpu"], default=None)
    p.add_argument("--model-id", default=None)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    cfg = Config.from_env()
    if args.host:
        cfg = Config(**{**cfg.__dict__, "host": args.host})
    if args.port:
        cfg = Config(**{**cfg.__dict__, "port": args.port})
    if args.device:
        cfg = Config(**{**cfg.__dict__, "device": args.device})
    if args.model_id:
        cfg = Config(**{**cfg.__dict__, "model_id": args.model_id})

    import uvicorn
    app = make_app(cfg)
    uvicorn.run(
        app,
        host=cfg.host,
        port=cfg.port,
        log_level="info" if not cfg.debug else "debug",
        access_log=cfg.debug,
    )


# uvicorn import-style entrypoint
app = make_app(Config.from_env())


if __name__ == "__main__":
    sys.exit(main() or 0)
