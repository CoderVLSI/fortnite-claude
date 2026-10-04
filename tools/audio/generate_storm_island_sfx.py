#!/usr/bin/env python3
"""Synthesise the vault / keycard / Warden / far-field / UI sounds (no API, no credits, deterministic).

    python3 tools/audio/generate_storm_island_sfx.py              # write the 12 new sounds + trim SMG / pistol shots
    python3 tools/audio/generate_storm_island_sfx.py vault_door   # just one
    python3 tools/audio/generate_storm_island_sfx.py --verify     # measure the files on disk
    python3 tools/audio/generate_storm_island_sfx.py --list

Needs numpy only. Self-contained (does not import the 22.05 kHz emote / event generators).
Output: mono, 44100 Hz, 16-bit PCM WAV, sample peak -3 dBFS (vault_alarm sits at -9 dBFS because it is meant to be
mid-quiet), exact length, 1 ms fade-in / 6 ms fade-out on one-shots, no digital silence padding longer than 50 ms.
vault_alarm is built from a circular buffer (periodic phase, circular filtering and reverb) so it loops without a click.

Weapon pass: shot_smg.wav and shot_pistol.wav are cut to 0.15 s (50 ms raised-cosine fade), resampled to 44.1 kHz and
normalised to -3 dBFS, overwriting the originals (full-auto SMG ~12/s and pistol ~6.7/s must not smear).
"""
import hashlib
import math
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
PEAK_DB = -3.0
SILENCE = 10 ** (-60.0 / 20)       # below this counts as silence when checking leading / trailing padding
MAX_PAD_S = 0.05
WEAPON_MAX_S = 0.15


# ------------------------------------------------------------------ building blocks

def tt(n):
    return np.arange(n) / SR


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def bq(x, kind, fc, q=0.7071):
    assert 10 < fc < 0.45 * SR, fc
    w = 2 * math.pi * fc / SR
    c, s = math.cos(w), math.sin(w)
    al = s / (2 * q)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:  # bp, constant 0 dB peak
        b = [al, 0.0, -al]
    a0 = 1 + al
    b0, b1, b2 = (v / a0 for v in b)
    a1, a2 = -2 * c / a0, (1 - al) / a0
    y = np.empty(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(np.asarray(x, dtype=float).tolist()):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, o
        y[i] = o
    return y


def periodic(x, fn):
    """Filter so the result is seamless around a loop point: run on 3 copies, keep the middle one."""
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def noise(rng, n):
    return rng.standard_normal(n)


def put(buf, t, sig, gain=1.0):
    i = int(round(t * SR))
    if i >= len(buf):
        return
    k = min(len(sig), len(buf) - i)
    buf[i:i + k] += sig[:k] * gain


def ramp(n, attack_s):
    return np.minimum(np.arange(n) / max(attack_s * SR, 1), 1.0)


def harmonics(ph, kmax, power=1.0, odd=False):
    """Band-limited stack of sines on a phase array (cycles)."""
    y = np.zeros(len(ph))
    for k in range(1, kmax + 1):
        if odd and k % 2 == 0:
            continue
        y += np.sin(2 * math.pi * k * ph) / k ** power
    return y


def finish(y, seconds, peak_db=PEAK_DB, loop=False, fade_out=0.006):
    n = int(round(seconds * SR))
    y = y[:n] if len(y) >= n else np.pad(y, (0, n - len(y)))
    y = y.copy()
    if not loop:
        a = int(0.001 * SR)
        y[:a] *= np.linspace(0, 1, a)
        k = int(fade_out * SR)
        y[-k:] *= (1 + np.cos(np.pi * np.arange(k) / k)) / 2
    return y * (10 ** (peak_db / 20) / np.max(np.abs(y)))


def reverb(x, rt60, lp_hz, seed, pre=0.015, circular=False, length=None):
    """Convolve with a synthetic exponentially decaying noise impulse response (unit energy)."""
    rng = np.random.default_rng(seed)
    n = len(x)
    m = int((length or min(rt60 * 1.1, 2.5)) * SR)
    if circular:
        m = min(m, n)
    t = tt(m)
    ir = noise(rng, m) * np.exp(-t * 6.908 / rt60)
    ir = bq(ir, "lp", lp_hz)
    p = int(pre * SR)
    ir[:p] = 0
    ir /= math.sqrt(np.sum(ir * ir))
    size = n if circular else 1 << int(math.ceil(math.log2(n + m)))
    out = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    return out[:n]


def metal_hit(base, dur, seed=0, bright=1.0):
    """Inharmonic struck-plate partials plus a tiny noise tick."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = tt(n)
    y = np.zeros(n)
    for r, a, d in [(1.0, 1.0, 0.30), (1.59, 0.7, 0.22), (2.14, 0.5, 0.17), (2.65, 0.35, 0.13), (3.5, 0.25 * bright, 0.09)]:
        y += a * np.sin(2 * math.pi * base * r * t + rng.uniform(0, 6.28)) * np.exp(-t / (dur * d * 2.2))
    y += bq(noise(rng, n), "bp", min(base * 2.2, 18000), 1.2) * np.exp(-t / 0.004) * 0.6
    return y * ramp(n, 0.0005)


def bell(freq, dur, tau, bright=0.4):
    n = int(dur * SR)
    t = tt(n)
    y = np.sin(2 * math.pi * freq * t) * np.exp(-t / tau)
    y += bright * np.sin(2 * math.pi * freq * 2.76 * t) * np.exp(-t / (tau * 0.4))
    y += 0.2 * np.sin(2 * math.pi * freq * 5.4 * t) * np.exp(-t / (tau * 0.2))
    return y * ramp(n, 0.0015)


def beep(freq, dur, rel=0.012, lp_hz=6000):
    n = int(dur * SR)
    ph = freq * tt(n)
    y = np.sign(np.sin(2 * math.pi * ph)) * 0.6 + np.sin(2 * math.pi * ph) * 0.8        # square + sine
    y = bq(y, "lp", lp_hz)
    i = np.arange(n)
    return y * ramp(n, 0.002) * np.minimum((n - i) / (rel * SR), 1.0)


# ------------------------------------------------------------------ vaults and keycards

def heavy_clunk(dur, seed, depth=1.0):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * math.pi * np.cumsum(46 + 70 * np.exp(-t / 0.035)) / SR) * np.exp(-t / 0.12) * depth
    knock = bq(noise(rng, n), "lp", 1100) * np.exp(-t / 0.02) * 0.9
    metal = sum(a * np.sin(2 * math.pi * f * t) * np.exp(-t / d) for f, a, d in
                [(310, 0.35, 0.07), (490, 0.28, 0.05), (744, 0.2, 0.04), (1020, 0.12, 0.03)])
    click = bq(noise(rng, n), "bp", 2800, 1.0) * np.exp(-t / 0.003) * 0.6
    return (body + knock + metal + click) * ramp(n, 0.0005)


def vault_unlock():
    rng = np.random.default_rng(201)
    buf = np.zeros(int(1.6 * SR))
    put(buf, 0.004, beep(1760, 0.075), 0.55)                       # keycard beep-beep, the second one higher
    put(buf, 0.105, beep(2349.3, 0.12), 0.65)
    put(buf, 0.30, heavy_clunk(0.4, 2011), 1.2)                    # bolt slides home
    put(buf, 0.435, heavy_clunk(0.2, 2012, 0.4), 0.55)             # latch drops
    n = int(0.98 * SR)
    t = tt(n)
    hiss = bq(bq(noise(rng, n), "hp", 2400), "lp", 11000)          # pneumatic release, "pshhhh"
    hiss *= ramp(n, 0.012) * np.exp(-t / 0.36) * np.minimum((0.98 - t) / 0.2, 1) * (1 + 0.1 * np.sin(2 * math.pi * 6 * t))
    burst = bq(noise(rng, n), "bp", 1800, 0.6) * np.exp(-t / 0.05) * 0.6
    put(buf, 0.62, hiss * 0.9 + burst, 0.7)
    return finish(buf, 1.6)


def vault_door():
    rng = np.random.default_rng(202)
    n = int(2.2 * SR)
    t = tt(n)
    run = ramp(n, 0.15) * np.minimum(np.maximum(1.80 - t, 0) / 0.1, 1) * (t < 1.80)         # door is moving
    pitch = 50 + 36 * smooth((t - 0.1) / 1.5)                                                # servo winds up
    ph = np.cumsum(pitch) / SR
    motor = bq(harmonics(ph, 14, 0.8), "lp", 1100) * (1 + 0.35 * np.sin(2 * math.pi * 24 * t)) * run   # gear-tooth grind
    sub = np.sin(2 * math.pi * np.cumsum(34 + 8 * smooth(t / 1.6)) / SR) * run * 1.1
    slow = lambda per, depth: 1 + depth * np.interp(t, np.linspace(0, 2.2, int(2.2 * per) + 2), rng.uniform(-1, 1, int(2.2 * per) + 2))
    scrape = (bq(noise(rng, n), "bp", 1500, 2.5) * 1.0 + bq(noise(rng, n), "bp", 2600, 3.0) * 0.7
              + bq(noise(rng, n), "bp", 3700, 3.0) * 0.4) * slow(14, 0.7) * np.clip(slow(5, 0.8), 0, None)
    scrape *= smooth((t - 0.25) / 0.3) * np.minimum(np.maximum(1.75 - t, 0) / 0.15, 1) * (t < 1.75) * 0.5
    rattle = bq(noise(rng, n), "lp", 380) * run * 0.5 * (1 + 0.5 * np.sin(2 * math.pi * 17 * t))
    y = motor * 0.6 + sub * 0.75 + scrape * 1.1 + rattle * 0.8
    m = int(0.38 * SR)                                                                       # final heavy thud
    u = tt(m)
    thud = np.sin(2 * math.pi * np.cumsum(30 + 65 * np.exp(-u / 0.05)) / SR) * np.exp(-u / 0.16) * 1.8
    thud += bq(noise(rng, m), "lp", 300) * np.exp(-u / 0.1) * 1.0
    thud += metal_hit(210, 0.38, 7) * 0.45
    thud += bq(noise(rng, m), "lp", 140) * np.exp(-u / 0.3) * 0.6                          # dust / rumble tail
    put(y, 1.82, thud * ramp(m, 0.0006), 1.6)
    return finish(y, 2.2, fade_out=0.05)


def keycard_pickup():
    rng = np.random.default_rng(203)
    buf = np.zeros(int(0.6 * SR))
    click = bq(noise(rng, int(0.02 * SR)), "bp", 3600, 1.0) * np.exp(-tt(int(0.02 * SR)) / 0.0025)
    thock = bq(noise(rng, int(0.03 * SR)), "lp", 1400) * np.exp(-tt(int(0.03 * SR)) / 0.006)
    put(buf, 0.0, click, 0.9)
    put(buf, 0.0, thock, 0.5)
    put(buf, 0.115, click, 0.45)                                           # card seats in the slot

    def chirp(f0, f1, dur):
        k = int(dur * SR)
        u = tt(k)
        f = f0 * (f1 / f0) ** (u / dur)
        ph = np.cumsum(f) / SR
        return (np.sin(2 * math.pi * ph) + 0.3 * np.sin(4 * math.pi * ph)) * ramp(k, 0.003) \
            * np.minimum((k - np.arange(k)) / (0.01 * SR), 1) * np.exp(-u / (dur * 1.4))
    put(buf, 0.008, chirp(1400, 3100, 0.075), 0.7)
    put(buf, 0.085, chirp(2100, 4400, 0.09), 0.8)
    for t0, f, g in [(0.17, 3136, 0.7), (0.22, 3951, 0.6), (0.28, 4699, 0.5), (0.34, 6272, 0.3)]:   # sparkle: "special"
        put(buf, t0, bell(f, 0.28, 0.07, 0.3), g)
    n = int(0.4 * SR)
    put(buf, 0.17, bq(noise(rng, n), "hp", 8000) * np.exp(-tt(n) / 0.1) * ramp(n, 0.02), 0.06)
    return finish(buf, 0.6, fade_out=0.06)


def keycard_deny():
    rng = np.random.default_rng(204)
    buf = np.zeros(int(0.5 * SR))

    def buzz(f, dur, rel=0.02):
        n = int(dur * SR)
        t = tt(n)
        ph = f * t
        y = (2 * (ph % 1.0) - 1) * 0.7 + np.sign(np.sin(2 * math.pi * ph * 1.5)) * 0.4          # raw but tonal
        y = bq(y, "lp", 1500, 0.9)
        y *= 1 + 0.35 * np.sin(2 * math.pi * 70 * t)
        y += bq(noise(rng, n), "bp", 700, 1.0) * 0.12
        i = np.arange(n)
        return y * ramp(n, 0.003) * np.minimum((n - i) / (rel * SR), 1.0)
    put(buf, 0.0, buzz(118, 0.2), 1.0)
    put(buf, 0.25, buzz(98, 0.25, 0.06), 1.0)
    return finish(buf, 0.5, fade_out=0.04)


def vault_alarm():
    n = 3 * SR
    t = tt(n)
    cyc = 1.5                                                              # two wails per loop
    u = (t % cyc)
    f = 400 + 150 * smooth(u / 0.7) - 40 * smooth((u - 1.0) / 0.2)
    f *= round(float(np.sum(f)) / SR) / (np.sum(f) / SR)                   # whole number of cycles, so the phase wraps
    ph = np.cumsum(f) / SR
    y = harmonics(ph, 15, 1.0, odd=True) + 0.5 * harmonics(ph * 1.003, 9, 1.2)           # klaxon: reedy, odd-heavy
    env = smooth(u / 0.16) * smooth((1.15 - u) / 0.3)
    y = periodic(y * env, lambda z: bq(bq(z, "lp", 950, 0.9), "bp", 620, 0.6) * 1.5 + bq(z, "lp", 700))   # muffled by distance
    wet = reverb(y, 1.1, 1300, 205, pre=0.04, circular=True, length=1.6)                  # far-off space, wraps seamlessly
    mix = y * 0.35 + wet * 1.0
    return finish(mix, 3.0, peak_db=-9.0, loop=True)


# ------------------------------------------------------------------ bosses

def warden_spawn():
    rng = np.random.default_rng(206)
    n = int(2.0 * SR)
    t = tt(n)
    swell = np.where(t < 1.05, smooth(t / 0.95) ** 0.9, np.exp(-(t - 1.05) / 0.3))
    glide = 1 + 0.035 * smooth(t / 1.0) - 0.05 * smooth((t - 1.2) / 0.8)
    vib = 1 + 0.004 * np.sin(2 * math.pi * 4.6 * t) * smooth(t / 0.6)
    voices = np.zeros(n)
    for f0, g in [(58.27, 1.0), (69.30, 0.55), (87.31, 0.7), (116.5, 0.35)]:           # Bb - Db - F: dark minor stack
        for det in (-0.006, 0.0, 0.007):
            ph = np.cumsum(f0 * (1 + det) * glide * vib) / SR
            voices += g * harmonics(ph, 22, 1.0) / 3
    dark = bq(voices, "lp", 420)
    bright = bq(voices, "lp", 1900)
    horn = dark * (1 - smooth(t / 1.0) * 0.7) + bright * smooth(t / 1.0) * 0.8
    horn += bq(horn, "bp", 330, 1.5) * 0.8                                           # brass bell resonance
    sub = np.sin(2 * math.pi * np.cumsum(29.1 * glide) / SR) * 0.5
    breath = bq(noise(rng, n), "lp", 700) * 0.12 * (0.4 + smooth(t / 0.9))
    dry = (horn + sub + breath) * swell
    y = dry * 0.8 + reverb(dry, 1.2, 1500, 206, pre=0.03, length=1.3) * 0.7
    y *= np.minimum((2.0 - t) / 0.3, 1.0)
    return finish(y, 2.0, fade_out=0.02)


def warden_down():
    rng = np.random.default_rng(207)
    buf = np.zeros(int(1.5 * SR))
    m = int(0.5 * SR)
    u = tt(m)
    drop = np.sin(2 * math.pi * np.cumsum(32 + 55 * np.exp(-u / 0.06)) / SR) * np.exp(-u / 0.17) * 1.7     # body hits ground
    drop += bq(noise(rng, m), "lp", 420) * np.exp(-u / 0.06) * 1.1
    drop += bq(noise(rng, m), "lp", 160) * np.exp(-u / 0.22) * 0.6
    put(buf, 0.0, drop * ramp(m, 0.0008), 1.5)
    put(buf, 0.0, bq(noise(rng, 900), "bp", 1800, 0.8) * np.exp(-tt(900) / 0.004), 0.7)
    for k in range(34):                                                             # plate armour clattering to rest
        t0 = 0.07 + 0.78 * rng.random() ** 1.7
        f = math.exp(rng.uniform(math.log(450), math.log(3200)))
        g = (1.0 - 0.8 * (t0 / 0.85)) * rng.uniform(0.35, 0.9)
        put(buf, t0, metal_hit(f, rng.uniform(0.07, 0.2), 2070 + k, 0.8), g * 0.5)
        if k % 3 == 0:
            q = int(0.05 * SR)
            put(buf, t0, bq(noise(rng, q), "bp", rng.uniform(900, 2200), 1.0) * np.exp(-tt(q) / 0.012), g * 0.6)
    start, dur = 0.74, 0.76                                                         # keycard drops: rising shimmer
    for k, name in enumerate([1319, 1568, 1976, 2349, 2637, 3136, 3951, 4699]):
        put(buf, start + 0.06 * k, bell(name, 0.4, 0.11, 0.35), 0.28 + 0.045 * k)
    n = int(dur * SR)
    s = tt(n)
    air = bq(noise(rng, n), "hp", 6500) * smooth(s / 0.4) * np.exp(-np.maximum(s - 0.4, 0) / 0.18)
    swp = np.sin(2 * math.pi * np.cumsum(900 * (6.5 ** (s / 0.55))) / SR) * smooth(s / 0.5) * np.exp(-np.maximum(s - 0.5, 0) / 0.1) * 0.15
    put(buf, start, air * 0.22 + swp, 1.0)
    buf *= np.minimum((1.5 - tt(len(buf))) / 0.2, 1.0)
    return finish(buf, 1.5, fade_out=0.02)


# ------------------------------------------------------------------ far-field (bigger map, 100 players)

def _far_shot(rng, gain):
    n = int(0.3 * SR)
    t = tt(n)
    crack = bq(noise(rng, n), "lp", 2600) * np.exp(-t / 0.011)
    boom = bq(noise(rng, n), "lp", 650) * np.exp(-t / 0.045) * 0.8
    thump = np.sin(2 * math.pi * np.cumsum(130 * np.exp(-t / 0.04) + 55) / SR) * np.exp(-t / 0.05) * 0.7
    return (crack + boom + thump) * ramp(n, 0.0008) * gain


def _distant_gunfire(seed, times, rt60):
    rng = np.random.default_rng(seed)
    n = int(1.2 * SR)
    dry = np.zeros(n)
    for t0 in times:
        put(dry, t0, _far_shot(rng, rng.uniform(0.6, 1.0)))
    dry = bq(dry, "lp", 3200)
    echo = np.zeros(n)                                                              # slap back off distant hills
    for d, g in [(0.19, 0.4), (0.33, 0.25), (0.52, 0.15)]:
        put(echo, d, bq(dry, "lp", 1400), g)
    wet = reverb(dry + echo, rt60, 1800, seed + 1, pre=0.02, length=0.9)
    y = dry * 0.3 + wet * 1.0
    y *= np.minimum((1.2 - tt(n)) / 0.12, 1.0)
    return finish(y, 1.2, fade_out=0.02)


def distant_gunfire_a():
    return _distant_gunfire(208, [0.012, 0.21, 0.29, 0.47], 0.75)


def distant_gunfire_b():
    return _distant_gunfire(209, [0.015, 0.09, 0.165, 0.43, 0.58], 0.9)


def distant_gunfire_c():
    return _distant_gunfire(210, [0.01 + 0.085 * k for k in range(6)], 0.7)


def bus_horn_far():
    rng = np.random.default_rng(211)
    n = int(1.5 * SR)
    t = tt(n)
    doppler = 1.022 - 0.045 * smooth((t - 0.1) / 1.3)                                # passes overhead: pitch falls
    vib = 1 + 0.003 * np.sin(2 * math.pi * 5.5 * t)
    env = ramp(n, 0.045) * np.where(t < 1.0, 1.0, np.exp(-(t - 1.0) / 0.2)) * (1 + 0.05 * np.sin(2 * math.pi * 3 * t))
    y = np.zeros(n)
    for f0, g in [(196.0, 1.0), (246.9, 0.8), (392.0, 0.25)]:                          # two-tone air horn chord
        for det in (-0.004, 0.004):
            y += g * harmonics(np.cumsum(f0 * (1 + det) * doppler * vib) / SR, 16, 1.0) / 2
    y = bq(y, "lp", 1700) + bq(y, "bp", 560, 1.2) * 0.6                             # air absorption: dull and distant
    y += bq(noise(rng, n), "bp", 900, 0.8) * 0.05
    dry = y * env
    mix = dry * 0.7 + reverb(dry, 0.9, 1500, 211, pre=0.04, length=1.0) * 0.6
    mix *= np.minimum((1.5 - t) / 0.2, 1.0)
    return finish(mix, 1.5, fade_out=0.02)


def players_left_ping():
    rng = np.random.default_rng(212)
    n = int(0.4 * SR)
    t = tt(n)
    y = np.sin(2 * math.pi * 1568 * t) * np.exp(-t / 0.085)
    y += 0.3 * np.sin(2 * math.pi * 3136 * t) * np.exp(-t / 0.035)
    y += 0.12 * np.sin(2 * math.pi * 784 * t) * np.exp(-t / 0.12)
    y += bq(noise(rng, n), "bp", 3500, 1.0) * np.exp(-t / 0.0025) * 0.35                  # the soft tick
    y *= ramp(n, 0.0015)
    return finish(y, 0.4, fade_out=0.07)


SOUNDS = {
    "vault_unlock": (vault_unlock, 1.6), "vault_door": (vault_door, 2.2), "keycard_pickup": (keycard_pickup, 0.6),
    "keycard_deny": (keycard_deny, 0.5), "vault_alarm": (vault_alarm, 3.0), "warden_spawn": (warden_spawn, 2.0),
    "warden_down": (warden_down, 1.5), "distant_gunfire_a": (distant_gunfire_a, 1.2),
    "distant_gunfire_b": (distant_gunfire_b, 1.2), "distant_gunfire_c": (distant_gunfire_c, 1.2),
    "bus_horn_far": (bus_horn_far, 1.5), "players_left_ping": (players_left_ping, 0.4),
}
PEAKS = {"vault_alarm": -9.0}
WEAPONS = ["shot_smg", "shot_pistol"]


# ------------------------------------------------------------------ files

def write_wav(path, y):
    pcm = np.round(np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        info = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0, info


def write_import(name):
    """Godot 3 .import stub (same params as the other sounds; the cache path is md5 of the res:// path)."""
    path = os.path.join(OUT, name + ".wav.import")
    if os.path.exists(path):
        return
    res = "res://assets/audio/%s.wav" % name
    dest = "res://.import/%s.wav-%s.sample" % (name, hashlib.md5(res.encode()).hexdigest())
    with open(path, "w") as f:
        f.write('[remap]\n\nimporter="wav"\ntype="AudioStreamSample"\npath="%s"\n\n[deps]\n\nsource_file="%s"\n'
                'dest_files=[ "%s" ]\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\n'
                'force/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\nedit/loop_begin=0\n'
                'edit/loop_end=-1\ncompress/mode=1\n' % (dest, res, dest))


def trim_weapon(name):
    """Cut a gunshot to WEAPON_MAX_S, fade the cut, resample to 44.1 kHz and normalise to -3 dBFS (idempotent)."""
    path = os.path.join(OUT, name + ".wav")
    y, (ch, _w, sr) = read_wav_any(path)
    if sr == SR and len(y) <= int(WEAPON_MAX_S * SR):
        return False
    y = y[:int(round(WEAPON_MAX_S * sr))]
    k = int(0.05 * sr)
    y[-k:] *= (1 + np.cos(np.pi * np.arange(k) / k)) / 2
    if sr != SR:
        m = int(round(len(y) * SR / sr))
        y = np.fft.irfft(np.fft.rfft(y), m) * (m / len(y))                       # spectral zero-pad upsample
    y = y[:int(WEAPON_MAX_S * SR)]
    write_wav(path, y * (10 ** (PEAK_DB / 20) / np.max(np.abs(y))))
    return True


def read_wav_any(path):
    with wave.open(path, "rb") as w:
        info = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        assert info[:2] == (1, 2), path
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0, info


# ------------------------------------------------------------------ verification

def _pad(y):
    nz = np.nonzero(np.abs(y) >= SILENCE)[0]
    return nz[0] / SR, (len(y) - 1 - nz[-1]) / SR


def verify(name):
    path = os.path.join(OUT, name + ".wav")
    y, info = read_wav(path)
    want = SOUNDS[name][1]
    target = PEAKS.get(name, PEAK_DB)
    peak = 20 * math.log10(float(np.max(np.abs(y))) + 1e-12)
    rms = math.sqrt(float(np.mean(y * y)))
    lead, trail = _pad(y)
    loop = name == "vault_alarm"
    checks = {
        "format": info == (1, 2, SR),
        "length": len(y) == int(round(want * SR)),
        "peak": abs(peak - target) <= 0.1 and peak < -1.0,
        "audible": rms > 0.005 and bool(np.all(np.isfinite(y))),
    }
    seam = ref = 0.0
    if loop:
        z = np.concatenate([y[-64:], y[:64]])
        seam = float(np.max(np.abs(np.diff(z, 2))))
        ref = float(np.percentile(np.abs(np.diff(y, 2)), 99.9))
        checks["seam"] = seam <= 2.0 * ref
    else:
        checks["pad"] = lead <= MAX_PAD_S and trail <= MAX_PAD_S
        checks["ends_zero"] = abs(y[0]) < 0.01 and abs(y[-1]) < 0.01
    return dict(name=name, dur=len(y) / SR, want=want, peak=peak, target=target, rms=20 * math.log10(rms), lead=lead,
                trail=trail, seam=seam, ref=ref, loop=loop, ok=all(checks.values()), failed=[k for k, v in checks.items() if not v])


def verify_weapon(name):
    y, info = read_wav(os.path.join(OUT, name + ".wav"))
    peak = 20 * math.log10(float(np.max(np.abs(y))) + 1e-12)
    lead, trail = _pad(y)
    ok = info == (1, 2, SR) and len(y) <= int(WEAPON_MAX_S * SR) and abs(peak - PEAK_DB) <= 0.1 and lead <= MAX_PAD_S
    return dict(name=name, dur=len(y) / SR, want=WEAPON_MAX_S, peak=peak, target=PEAK_DB, rms=20 * math.log10(math.sqrt(float(np.mean(y * y)))),
                lead=lead, trail=trail, seam=0.0, ref=0.0, loop=False, ok=ok, failed=[] if ok else ["weapon"])


def report(rows):
    print("%-18s %7s %7s %9s %9s %8s %8s  %s" % ("file", "want s", "len s", "peak dBFS", "rms dBFS", "lead ms", "trail ms", "result"))
    for r in rows:
        extra = ("  seam d2 %.5f vs %.5f" % (r["seam"], r["ref"])) if r["loop"] else ""
        print("%-18s %7.3f %7.3f %9.2f %9.1f %8.1f %8.1f  %s%s" % (
            r["name"], r["want"], r["dur"], r["peak"], r["rms"], r["lead"] * 1000, r["trail"] * 1000,
            "PASS" if r["ok"] else "FAIL " + ",".join(r["failed"]), extra))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        for n, (_f, s) in SOUNDS.items():
            print("%-18s %.2f s" % (n, s))
        for n in WEAPONS:
            print("%-18s <= %.2f s (trimmed)" % (n, WEAPON_MAX_S))
        return
    names = [a for a in args if a in SOUNDS] or ([] if args else list(SOUNDS))
    do_weapons = not args or any(a in WEAPONS for a in args)
    if "--verify" not in sys.argv:
        for n in names:
            write_wav(os.path.join(OUT, n + ".wav"), SOUNDS[n][0]())
            write_import(n)
            print("wrote", n)
        if do_weapons:
            for n in WEAPONS:
                if not args or n in args:
                    print(("trimmed " if trim_weapon(n) else "already trimmed ") + n)
    rows = [verify(n) for n in names] + ([verify_weapon(n) for n in WEAPONS] if do_weapons else [])
    report(rows)
    sys.exit(0 if all(r["ok"] for r in rows) else 1)


if __name__ == "__main__":
    main()
