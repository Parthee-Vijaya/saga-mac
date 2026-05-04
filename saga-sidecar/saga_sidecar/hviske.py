"""Hviske v5.3 model wrapper.

Hviske er en Conformer-baseret encoder-decoder ASR (2B parametre), finjusteret
til dansk. Modellen bruger ``trust_remote_code=True`` så Transformers henter
custom Conformer-kode fra Hugging Face — sørg for at have et tillidsfuldt netværk
ved første load.

Inference bruger modellens egen ``model.transcribe()``-helper (defineret i den
custom model-class). Den håndterer prompt-tokens for sprog (`<|da|>`),
punctuation og auto-chunking af lange clips. Det er DEN officielle API, ikke
``generate()`` direkte — sidstnævnte producerer multilingual junk uden den
korrekte prompt.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Literal

import numpy as np
import torch

logger = logging.getLogger(__name__)

Device = Literal["mps", "cuda", "cpu"]


def pick_device(preference: str = "auto") -> Device:
    if preference == "cuda" and torch.cuda.is_available():
        return "cuda"
    if preference == "mps" and torch.backends.mps.is_available():
        return "mps"
    if preference == "cpu":
        return "cpu"
    if preference == "auto":
        if torch.cuda.is_available():
            return "cuda"
        if torch.backends.mps.is_available():
            return "mps"
        return "cpu"
    raise ValueError(f"Ukendt device-preference: {preference}")


def pick_dtype(device: Device) -> torch.dtype:
    if device == "cuda":
        return torch.bfloat16
    if device == "mps":
        # MPS understøtter bf16 på macOS 14+ med PyTorch 2.5+. Override via env:
        #   SAGA_FORCE_FP32=1  (større numerical safety, ~3× langsommere)
        #   SAGA_FORCE_FP16=1  (uunderstøttet for Hviske — overflow)
        if os.getenv("SAGA_FORCE_FP32") == "1":
            return torch.float32
        if os.getenv("SAGA_FORCE_FP16") == "1":
            return torch.float16
        return torch.bfloat16
    return torch.float32


class HviskeASR:
    """Lazy-loaded Hviske-wrapper. Indlæser model ved første transcribe-call."""

    def __init__(self, model_id: str = "syvai/hviske-v5.3", device: str = "auto") -> None:
        self.model_id = model_id
        self.device: Device = pick_device(device)
        self.dtype = pick_dtype(self.device)
        self._processor = None
        self._model = None

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def load(self) -> None:
        if self.is_loaded:
            return
        # Lazy import — transformers er en tung import
        from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor

        logger.info("Indlæser Hviske '%s' på %s (%s)", self.model_id, self.device, self.dtype)
        t0 = time.perf_counter()

        self._processor = AutoProcessor.from_pretrained(self.model_id, trust_remote_code=True)

        kwargs: dict = {"trust_remote_code": True, "dtype": self.dtype}
        self._model = AutoModelForSpeechSeq2Seq.from_pretrained(self.model_id, **kwargs)
        self._model = self._model.to(self.device).eval()

        elapsed = time.perf_counter() - t0
        logger.info("Hviske loaded på %.1fs", elapsed)

    @torch.inference_mode()
    def transcribe(
        self,
        audio: np.ndarray,
        sample_rate: int = 16_000,
        num_beams: int = 1,  # noqa: ARG002 — bevaret for fremtidig brug; transcribe() bruger greedy
        language: str = "da",
        punctuation: bool = True,
    ) -> dict:
        """Transcriberer mono float32 audio. Returnerer { text, duration_ms, inference_ms, rtf }."""
        if not self.is_loaded:
            self.load()
        assert self._processor is not None and self._model is not None

        if audio.ndim != 1:
            raise ValueError(f"Forventede mono audio (1-D), fik shape {audio.shape}")

        duration_s = len(audio) / sample_rate
        t0 = time.perf_counter()

        # Brug model.transcribe() — den officielle API. Den bygger den korrekte
        # decoder-prompt med <|startoftranscript|><|da|><|da|><|pnc|>... osv.,
        # auto-chunker lange clips og samler resultaterne sammen.
        results = self._model.transcribe(
            processor=self._processor,
            language=language,
            audio_arrays=[audio.astype(np.float32, copy=False)],
            sample_rates=[sample_rate],
            punctuation=punctuation,
        )
        text = (results[0] if results else "").strip()

        inference_s = time.perf_counter() - t0
        rtf = inference_s / duration_s if duration_s > 0 else 0.0

        return {
            "text": text,
            "duration_ms": int(duration_s * 1000),
            "inference_ms": int(inference_s * 1000),
            "rtf": round(rtf, 4),
        }

    def warmup(self) -> None:
        """Kør én kort transcription for at varme op (cudnn / metal kernel-compilation).

        Bruger 2 sekunder stilhed — modellen returnerer typisk tom streng eller minimal punktuering.
        """
        if not self.is_loaded:
            self.load()
        silence = np.zeros(32_000, dtype=np.float32)  # 2 sekunder stilhed
        try:
            self.transcribe(silence)
        except Exception as e:  # noqa: BLE001
            logger.warning("Warmup fejlede (ikke kritisk): %s", e)
