"""Audio decoding + resampling helpers."""

from __future__ import annotations

import io

import numpy as np
import soundfile as sf


def decode_audio_bytes(data: bytes, target_sr: int = 16_000) -> tuple[np.ndarray, int]:
    """Decode arbitrary audio bytes (WAV, FLAC, OGG, raw PCM) to mono float32 np-array.

    Returns (samples, sample_rate). Resamples to target_sr if needed.
    """
    # soundfile auto-detects format from header
    audio, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=False)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)  # downmix til mono

    if sr != target_sr:
        audio = _resample_linear(audio, sr, target_sr)
        sr = target_sr

    return audio.astype(np.float32, copy=False), sr


def decode_raw_pcm16(data: bytes, sample_rate: int) -> np.ndarray:
    """Decode raw 16-bit signed little-endian PCM mono → float32 [-1, 1]."""
    pcm = np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0
    return pcm


def _resample_linear(audio: np.ndarray, from_sr: int, to_sr: int) -> np.ndarray:
    """Lightweight linear resampling. For higher quality, swap til librosa.resample."""
    if from_sr == to_sr:
        return audio
    ratio = to_sr / from_sr
    new_len = int(round(len(audio) * ratio))
    if new_len == 0:
        return np.zeros(0, dtype=np.float32)
    x_new = np.linspace(0.0, 1.0, new_len, endpoint=False)
    x_old = np.linspace(0.0, 1.0, len(audio), endpoint=False)
    return np.interp(x_new, x_old, audio).astype(np.float32)
