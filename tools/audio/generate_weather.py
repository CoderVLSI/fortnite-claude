#!/usr/bin/env python3
"""Synthesise the weather sounds: rain_loop (8 s seamless loop) and thunder (3.5 s).

    python3 tools/audio/generate_weather.py     # needs numpy + scipy
    -> assets/audio/rain_loop.wav, assets/audio/thunder.wav   (22.05 kHz, 16-bit mono)

rain_loop is built entirely with circular (FFT) filtering and periodic modulation, so its last
sample flows straight into its first one: no crossfade, no click at the seam.
"""
import os

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
RNG = np.random.default_rng(2024)


def write(name, x, peak=0.85):
    x = np.asarray(x, dtype=float)
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("  %-12s %5.2fs" % (name, len(x) / SR))


def circ_filter(x, shape):
    """Filter x in the frequency domain with shape(freq_hz) -> gain; circular, hence loop-safe."""
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(np.fft.rfft(x) * shape(f), len(x))


def rain_loop():
    n = 8 * SR
    t = np.arange(n) / SR
    # steady wash: band-limited noise, gentle high-frequency roll-off (soft on grass and leaves)
    wash = circ_filter(RNG.standard_normal(n),
                       lambda f: np.where((f > 500) & (f < 9000), 1 / np.sqrt(np.maximum(f, 500) / 500), 0) *
                       np.exp(-(f / 6500) ** 2))
    wash /= np.std(wash)
    # low body of the downpour
    body = circ_filter(RNG.standard_normal(n), lambda f: np.exp(-(f / 450) ** 2) * (f > 60))
    body /= np.std(body)
    # drops: sparse tiny resonant ticks scattered around the loop (wrapped, so the seam is clean)
    drops = np.zeros(n)
    for _ in range(420):
        i = int(RNG.integers(0, n))
        freq = RNG.uniform(1500, 5500)
        k = np.arange(int(0.012 * SR))
        tick = np.sin(2 * np.pi * freq * k / SR) * np.exp(-k / SR * 450) * RNG.uniform(0.15, 0.6)
        idx = (i + k) % n
        drops[idx] += tick
    # slow, whole-cycle periodic swell
    swell = 1 + 0.12 * np.sin(2 * np.pi * t / 8 * 1) + 0.07 * np.sin(2 * np.pi * t / 8 * 3 + 1.3)
    x = (wash * 0.9 + body * 0.35 + drops * 0.5 * np.std(wash)) * swell
    write("rain_loop", x, peak=0.55)


def thunder():
    n = int(3.5 * SR)
    t = np.arange(n) / SR
    b, a = signal.butter(2, 180 / (SR / 2))
    rumble = signal.lfilter(b, a, RNG.standard_normal(n))
    rumble /= np.std(rumble)
    # distant roll: a soft onset, a few swelling peaks, long fade
    env = np.minimum(1, t / 0.35) * np.exp(-t / 1.15)
    for at, g in ((0.7, 0.5), (1.4, 0.35), (2.1, 0.22)):
        env += g * np.exp(-((t - at) / 0.22) ** 2) * np.exp(-t / 2.0)
    # crackly mid layer that thins out and darkens as the sound recedes
    crack = signal.lfilter(*signal.butter(2, [120 / (SR / 2), 900 / (SR / 2)], "band"), RNG.standard_normal(n))
    crack /= np.std(crack)
    crack *= np.exp(-t / 0.5) * np.minimum(1, t / 0.08) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 3.1 * t)))
    sub = np.sin(2 * np.pi * (48 - 14 * t / 3.5) * t) * np.exp(-t / 1.3) * np.minimum(1, t / 0.2)
    x = rumble * env * 0.9 + crack * 0.35 + sub * 0.5
    x *= np.minimum(1, (n - np.arange(n)) / (0.25 * SR))  # fade to silence at the end
    write("thunder", x)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rain_loop()
    thunder()
