"""Tests for audio decode/resample helpers."""

from __future__ import annotations

import io

import numpy as np
import soundfile as sf

from saga_sidecar.audio import decode_audio_bytes, decode_raw_pcm16


def test_decode_pcm16_roundtrip():
    pcm = np.array([0, 16384, -16384, 32767, -32768], dtype="<i2")
    decoded = decode_raw_pcm16(pcm.tobytes(), 16_000)
    expected = np.array([0.0, 0.5, -0.5, 32767 / 32768, -1.0], dtype=np.float32)
    np.testing.assert_allclose(decoded, expected, atol=1e-4)


def test_decode_wav_mono_16k():
    sr = 16_000
    samples = (np.sin(np.linspace(0, 2 * np.pi, sr)) * 0.5).astype(np.float32)
    buf = io.BytesIO()
    sf.write(buf, samples, sr, format="WAV", subtype="PCM_16")
    decoded, decoded_sr = decode_audio_bytes(buf.getvalue(), target_sr=16_000)
    assert decoded_sr == 16_000
    assert decoded.shape == samples.shape
    assert decoded.dtype == np.float32


def test_decode_wav_resamples_44k_to_16k():
    sr = 44_100
    samples = np.zeros(sr, dtype=np.float32)
    buf = io.BytesIO()
    sf.write(buf, samples, sr, format="WAV", subtype="PCM_16")
    decoded, decoded_sr = decode_audio_bytes(buf.getvalue(), target_sr=16_000)
    assert decoded_sr == 16_000
    # Tilladt afvigelse pga. linear interp boundary
    assert abs(len(decoded) - 16_000) <= 2


def test_decode_stereo_downmixes_to_mono():
    sr = 16_000
    stereo = np.zeros((sr, 2), dtype=np.float32)
    stereo[:, 0] = 0.5
    stereo[:, 1] = -0.5
    buf = io.BytesIO()
    sf.write(buf, stereo, sr, format="WAV", subtype="PCM_16")
    decoded, _ = decode_audio_bytes(buf.getvalue(), target_sr=16_000)
    assert decoded.ndim == 1
    np.testing.assert_allclose(decoded, np.zeros(sr), atol=1e-3)
