"""Configuration loaded from env vars."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    model_id: str = "syvai/hviske-v5.3"
    device: str = "auto"
    port: int = 7861
    host: str = "127.0.0.1"
    debug: bool = False
    target_sample_rate: int = 16_000
    max_audio_seconds: int = 600
    num_beams: int = 1

    @classmethod
    def from_env(cls) -> "Config":
        return cls(
            model_id=os.getenv("SAGA_MODEL_ID", "syvai/hviske-v5.3"),
            device=os.getenv("SAGA_DEVICE", "auto"),
            port=int(os.getenv("SAGA_PORT", "7861")),
            host=os.getenv("SAGA_HOST", "127.0.0.1"),
            debug=os.getenv("SAGA_DEBUG", "0") == "1",
            target_sample_rate=int(os.getenv("SAGA_SR", "16000")),
            max_audio_seconds=int(os.getenv("SAGA_MAX_SECONDS", "600")),
            num_beams=int(os.getenv("SAGA_NUM_BEAMS", "1")),
        )
