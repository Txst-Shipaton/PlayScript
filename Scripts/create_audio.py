#!/usr/bin/env python3
"""Compose PlayScript's original, seamless ambient score. Requires numpy.

No samples or third-party music. Rounded sine voices, a slow repeating motif,
and a very soft overtone pad. Rendered once and bundled, never run by the app.
"""
from pathlib import Path
import wave
import numpy as np

RATE = 24000
DURATION = 32
OUT = Path(__file__).resolve().parents[1] / "PlayScript/Resources/Audio"
OUT.mkdir(parents=True, exist_ok=True)


def frequency(midi):
    # An integer number of cycles per loop eliminates discontinuities in the pad.
    hz = 440 * 2 ** ((midi - 69) / 12)
    return round(hz * DURATION) / DURATION


def write(name, samples):
    samples = np.asarray(samples)
    assert np.isfinite(samples).all()
    samples = samples / max(np.max(np.abs(samples)), 0.001) * 0.62
    with wave.open(str(OUT / f"{name}.wav"), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes((samples * 32767).astype('<i2').tobytes())


def score(name, chord, melody, brightness):
    t = np.arange(RATE * DURATION) / RATE
    signal = np.zeros_like(t)
    for i, note in enumerate(chord):
        f = frequency(note)
        breath = 0.8 + 0.2 * np.sin(2 * np.pi * t / DURATION + i)
        signal += 0.11 * breath * np.sin(2 * np.pi * f * t)
        signal += 0.018 * brightness * np.sin(2 * np.pi * f * 2 * t)
    # Circularly place each note and its tail, preserving the seamless loop.
    for i, note in enumerate(melody):
        age = (t - i * DURATION / len(melody)) % DURATION
        envelope = (1 - np.exp(-age / 0.08)) * np.exp(-age / 1.8)
        f = frequency(note)
        bell = np.sin(2 * np.pi * f * age) + 0.16 * np.sin(2 * np.pi * f * 2 * age)
        signal += 0.2 * brightness * envelope * bell
        # Quiet, rounded echo; same pitch, no sharp reward-like chime.
        echo_age = (age - 0.37) % DURATION
        echo_env = (1 - np.exp(-echo_age / 0.16)) * np.exp(-echo_age / 2.2)
        signal += 0.032 * brightness * echo_env * np.sin(2 * np.pi * f * echo_age)
    write(name, signal)


score('longing', [50, 57, 62, 65], [74, 77, 81, 77, 74, 72, 69, 72], 0.75)
score('tender', [53, 60, 65, 69], [77, 81, 84, 81, 79, 77, 76, 72], 0.85)
score('uneasy', [50, 57, 60, 65], [74, 72, 69, 65, 72, 69, 65, 62], 0.4)
score('grief', [46, 53, 58, 62], [74, 69, 65, 62, 69, 65, 62, 60], 0.28)
score('dawn', [53, 60, 64, 69], [77, 79, 81, 84, 81, 79, 77, 76], 0.8)

t = np.arange(int(RATE * 1.4)) / RATE
envelope = (1 - np.exp(-t / 0.055)) * np.exp(-t / 0.23)
write('choice', envelope * (np.sin(2 * np.pi * 523.25 * t) + 0.2 * np.sin(2 * np.pi * 783.99 * t)))
t = np.arange(int(RATE * 0.65)) / RATE
rng = np.random.default_rng(42)
noise = rng.normal(0, 1, len(t))
soft_noise = np.convolve(noise, np.ones(100) / 100, mode='same')
write('turn', soft_noise * np.sin(np.pi * t / 0.65) ** 3)
print(f"Created {len(list(OUT.glob('*.wav')))} original audio assets.")
