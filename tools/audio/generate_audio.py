#!/usr/bin/env python3
"""Synthesise every sound effect and music track of the game (no samples, no network).

    python3 tools/audio/generate_audio.py            # needs numpy + scipy
    -> assets/audio/*.wav   (22.05 kHz, 16-bit mono)

Sounds are built from filtered noise, sine / saw oscillators and exponential envelopes.
Loops (*_loop, music_*) are made seamless by folding the reverb tail back onto the start.
"""
import os

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
RNG = np.random.default_rng(1234)


# ----------------------------------------------------------------------------- primitives

class S(np.ndarray):
    """1-D float signal. Adding signals of different lengths zero-pads the shorter one."""

    def __new__(cls, a):
        return np.asarray(a, dtype=float).view(cls)

    def _combine(self, o, op):
        a = np.asarray(self)
        if isinstance(o, np.ndarray) and o.ndim == 1 and o.shape != a.shape:
            b = np.asarray(o)
            n = min(len(a), len(b)) if op is np.multiply else max(len(a), len(b))
            pa = np.zeros(n)
            pb = np.zeros(n)
            m = min(n, len(a))
            pa[:m] = a[:m]
            m = min(n, len(b))
            pb[:m] = b[:m]
            return S(op(pa, pb))
        return S(op(a, np.asarray(o) if isinstance(o, np.ndarray) else o))

    def __add__(self, o):
        return self._combine(o, np.add)

    __radd__ = __add__

    def __mul__(self, o):
        return self._combine(o, np.multiply)

    __rmul__ = __mul__

    def __sub__(self, o):
        return self._combine(o, np.subtract)

def N(sec):
    return int(sec * SR)


def noise(sec):
    return S(RNG.uniform(-1, 1, N(sec)))


def decay(n, rate):
    return S(np.exp(-np.arange(n) / SR * rate))


def sine(freq, sec, phase=0.0):
    f = np.full(N(sec), freq, dtype=float) if np.isscalar(freq) else np.asarray(freq, dtype=float)
    return S(np.sin(phase + 2 * np.pi * np.cumsum(f) / SR))


def sweep(f0, f1, sec, curve=1.0):
    x = np.linspace(0, 1, N(sec)) ** curve
    return sine(f0 + (f1 - f0) * x, sec)


def saw(freq, sec):
    f = np.full(N(sec), freq, dtype=float) if np.isscalar(freq) else np.asarray(freq, dtype=float)
    ph = (np.cumsum(f) / SR) % 1.0
    return S(2 * ph - 1)


def square(freq, sec):
    return S(np.sign(np.asarray(sine(freq, sec))))


def _butter(kind, freq, order=2):
    nyq = SR / 2
    if isinstance(freq, (list, tuple)):
        freq = [min(f, nyq * 0.95) / nyq for f in freq]
    else:
        freq = min(freq, nyq * 0.95) / nyq
    return signal.butter(order, freq, btype=kind)


def lp(x, f, order=2):
    b, a = _butter("low", f, order)
    return S(signal.lfilter(b, a, np.asarray(x)))


def hp(x, f, order=2):
    b, a = _butter("high", f, order)
    return S(signal.lfilter(b, a, np.asarray(x)))


def bp(x, lo, hi, order=2):
    b, a = _butter("band", [lo, hi], order)
    return S(signal.lfilter(b, a, np.asarray(x)))


def _pad(x, widths):
    return S(np.pad(np.asarray(x), widths))


def fit(x, n):
    x = np.asarray(x)
    if len(x) >= n:
        return S(x[:n])
    return S(np.pad(x, (0, n - len(x))))


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += np.asarray(p)
    return S(out)


def place(canvas, x, at_sec, gain=1.0):
    i = N(at_sec)
    if i >= len(canvas):
        return
    end = min(len(canvas), i + len(x))
    canvas[i:end] += x[:end - i] * gain


def fade(x, a=0.004, b=0.01):
    x = x.copy()
    na, nb = min(N(a), len(x)), min(N(b), len(x))
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def reverb(x, wet=0.3, size=1.0, tail=0.8):
    """Small Schroeder reverb: 4 combs + 2 all-passes."""
    n = len(x) + N(tail)
    x = fit(x, n)
    combs = []
    for d, g in ((0.0297, 0.80), (0.0371, 0.78), (0.0411, 0.76), (0.0437, 0.74)):
        dn = max(1, int(d * size * SR))
        a = np.zeros(dn + 1)
        a[0] = 1
        a[-1] = -g
        combs.append(signal.lfilter([1], a, x))
    y = sum(combs) / 4
    for d, g in ((0.005, 0.7), (0.0017, 0.7)):
        dn = max(1, int(d * SR))
        b = np.zeros(dn + 1)
        b[0] = -g
        b[-1] = 1
        a = np.zeros(dn + 1)
        a[0] = 1
        a[-1] = -g
        y = signal.lfilter(b, a, y)
    return S(np.asarray(x) * (1 - wet) + np.asarray(y) * wet * 2.2)


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def loopify(x, length_sec):
    """Fold anything after length_sec back onto the start so the loop is seamless."""
    L = N(length_sec)
    x = fit(x, max(len(x), L))
    x = np.asarray(x)
    out = x[:L].copy()
    tail = x[L:]
    out[:len(tail)] += tail[:L]
    return S(out)


def xfade_loop(x, sec=0.12):
    """Overlap the tail onto the head with complementary fades, then drop the tail."""
    x = np.asarray(x)
    n = min(N(sec), len(x) // 4)
    out = x[:-n].copy()
    out[:n] = out[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return out


def save(name, x, peak=0.9):
    is_loop = name.endswith("_loop") or (name.startswith("music_") and not name.endswith(("victory", "defeat")))
    x = np.asarray(x)
    if is_loop:
        x = xfade_loop(x)
    else:
        x = np.asarray(fade(x, 0.002, 0.01))
    x = np.clip(norm(x, peak), -1, 1)
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("  %-22s %5.2fs" % (name, len(x) / SR))


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------------------- weapons

def gunshot(body_hz, crack_lo, crack_hi, dur, punch, body_lp, tail, rev=0.25, crack_gain=1.0):
    n = N(dur)
    thump = sweep(body_hz * 2.2, body_hz, 0.08) * 1.0
    thump = fit(thump, n) * decay(n, 16)
    crack = bp(noise(dur), crack_lo, crack_hi) * decay(n, 55) * crack_gain
    body = lp(noise(dur), body_lp) * decay(n, 13)
    out = thump * punch + crack + body * 0.7
    return reverb(out, wet=rev, size=1.0 + tail * 0.4, tail=tail)


def make_weapons():
    save("shot_pistol", gunshot(150, 900, 5000, 0.3, 0.8, 2500, 0.3, 0.18))
    save("shot_smg", gunshot(170, 1200, 6000, 0.18, 0.55, 3000, 0.2, 0.12, 1.1))
    save("shot_rifle", gunshot(110, 800, 4500, 0.4, 1.1, 2200, 0.5, 0.25))
    save("shot_shotgun", gunshot(75, 400, 3500, 0.55, 1.5, 1800, 0.7, 0.3, 0.8))
    save("shot_sniper", gunshot(90, 600, 6500, 0.7, 1.4, 2800, 1.4, 0.4, 1.3))
    # mythic: rifle boom + rising energy ring
    base = gunshot(100, 800, 6000, 0.5, 1.2, 2500, 0.9, 0.35)
    ring = sweep(500, 2400, 0.5, 0.6) * decay(N(0.5), 6) * 0.35
    ring2 = sine(1760, 0.6) * decay(N(0.6), 5) * 0.12
    save("shot_mythic", mix(base, ring, ring2))
    save("dry_fire", fit(hp(noise(0.05), 1500) * decay(N(0.05), 120), N(0.06)) + fit(sine(220, 0.04) * decay(N(0.04), 90), N(0.06)) * 0.5)

    # reload: mag out, mag in, slide
    c = np.zeros(N(1.0))
    place(c, hp(noise(0.05), 800) * decay(N(0.05), 70) + sine(300, 0.05) * decay(N(0.05), 60) * 0.5, 0.05)
    place(c, bp(noise(0.12), 400, 3000) * decay(N(0.12), 25) * 0.7, 0.28)
    place(c, hp(noise(0.06), 900) * decay(N(0.06), 80) + sine(480, 0.06) * decay(N(0.06), 70) * 0.6, 0.55)
    place(c, sine(900, 0.04) * decay(N(0.04), 120) + hp(noise(0.05), 2000) * decay(N(0.05), 100), 0.78, 0.8)
    save("reload", c)
    pump = np.zeros(N(0.6))
    place(pump, hp(noise(0.08), 500) * decay(N(0.08), 50) + sine(200, 0.08) * decay(N(0.08), 40), 0.0)
    place(pump, hp(noise(0.08), 700) * decay(N(0.08), 55) + sine(260, 0.08) * decay(N(0.08), 40), 0.28)
    save("pump", pump)
    save("bolt", mix(hp(noise(0.06), 800) * decay(N(0.06), 60), _pad(hp(noise(0.06), 1000) * decay(N(0.06), 70), (N(0.3), 0))))

    # melee
    save("swing", fit(bp(noise(0.3), 300, 2400) * np.sin(np.linspace(0, np.pi, N(0.3))) ** 2, N(0.3)) * 0.8)
    save("hit_wood", lp(noise(0.18), 900) * decay(N(0.18), 30) + sine(190, 0.18) * decay(N(0.18), 28) * 0.7 + bp(noise(0.18), 1500, 3000) * decay(N(0.18), 70) * 0.3)
    save("hit_stone", hp(noise(0.2), 1500) * decay(N(0.2), 45) + sine(1300, 0.2) * decay(N(0.2), 28) * 0.4 + sine(2100, 0.2) * decay(N(0.2), 35) * 0.25)
    save("hit_metal", sine(880, 0.5) * decay(N(0.5), 7) * 0.6 + sine(1410, 0.5) * decay(N(0.5), 9) * 0.4 + sine(2250, 0.5) * decay(N(0.5), 12) * 0.25 + hp(noise(0.5), 3000) * decay(N(0.5), 80) * 0.4)
    save("hit_flesh", lp(noise(0.2), 600) * decay(N(0.2), 22) + sine(95, 0.2) * decay(N(0.2), 18) * 0.9)
    # feedback
    save("hitmarker", sine(2200, 0.07) * decay(N(0.07), 60) + sine(3300, 0.07) * decay(N(0.07), 80) * 0.4)
    kd = np.zeros(N(0.45))
    place(kd, sine(880, 0.2) * decay(N(0.2), 12), 0.0)
    place(kd, sine(1320, 0.3) * decay(N(0.3), 9), 0.09)
    save("kill_ding", kd)
    # grunts
    def grunt(f0, dur):
        f = np.linspace(f0 * 1.15, f0 * 0.8, N(dur))
        v = saw(f, dur) * 0.6
        v = bp(v, 300, 1500, 2) * 2
        return v * np.sin(np.linspace(0, np.pi, N(dur))) ** 0.6 * (0.7 + 0.3 * lp(noise(dur), 30))
    save("hurt", grunt(135, 0.28))
    d = sweep(260, 70, 0.7, 0.7)
    save("death", bp(saw(np.linspace(180, 55, N(0.7)), 0.7), 150, 900) * decay(N(0.7), 3.0) + lp(noise(0.7), 500) * decay(N(0.7), 6) * 0.4)


# ----------------------------------------------------------------------------- movement

def make_movement():
    def step(lo, hi, dur, gain):
        return bp(noise(dur), lo, hi) * decay(N(dur), 38) * gain
    save("step_grass", step(300, 2200, 0.13, 0.8) + lp(noise(0.13), 250) * decay(N(0.13), 30) * 0.7)
    save("step_sand", step(500, 4500, 0.16, 0.9) * 0.9)
    save("step_wood", lp(noise(0.12), 700) * decay(N(0.12), 36) + sine(160, 0.12) * decay(N(0.12), 35) * 0.8 + hp(noise(0.12), 2500) * decay(N(0.12), 90) * 0.2)
    save("step_water", bp(noise(0.25), 400, 3000) * decay(N(0.25), 16) * 0.9 + sine(np.linspace(500, 900, N(0.12)), 0.12) * decay(N(0.12), 25) * 0.3)
    save("jump", bp(noise(0.14), 300, 2500) * np.sin(np.linspace(0, np.pi, N(0.14))) * 0.7)
    save("land", lp(noise(0.22), 500) * decay(N(0.22), 18) + sine(80, 0.22) * decay(N(0.22), 16) * 0.8)
    save("mantle", bp(noise(0.5), 300, 2500) * np.sin(np.linspace(0, np.pi, N(0.5))) ** 2 * 0.8 + lp(noise(0.5), 400) * decay(N(0.5), 6) * 0.3)
    # water
    sp = bp(noise(0.9), 300, 5000) * decay(N(0.9), 5) + lp(noise(0.9), 700) * decay(N(0.9), 4) * 0.8
    bub = np.zeros(N(0.9))
    for i in range(8):
        f0 = RNG.uniform(400, 900)
        place(bub, sweep(f0, f0 * 2.0, 0.07) * decay(N(0.07), 40), RNG.uniform(0.05, 0.5), 0.25)
    save("splash", sp + bub)
    save("swim_stroke", bp(noise(0.4), 300, 3500) * np.sin(np.linspace(0, np.pi, N(0.4))) ** 1.5 * 0.9 + lp(noise(0.4), 500) * decay(N(0.4), 6) * 0.3)
    # ambient waves (seamless 8 s)
    L = 8.0
    sw = np.sin(2 * np.pi * np.arange(N(L)) / SR / L * 3) * 0.5 + 0.5
    waves = lp(noise(L), 900) * (0.25 + 0.6 * sw ** 2) + bp(noise(L), 1500, 5000) * (0.05 + 0.25 * sw ** 3)
    save("waves_loop", waves)


# ----------------------------------------------------------------------------- loot & items

def chime(notes, step=0.07, dur=0.5, wave="bell", gain=0.6):
    out = np.zeros(N(dur + step * len(notes)))
    for i, m in enumerate(notes):
        f = midi(m)
        if wave == "bell":
            tone = sine(f, dur) + 0.4 * sine(f * 2.76, dur) * decay(N(dur), 8) + 0.2 * sine(f * 5.4, dur) * decay(N(dur), 14)
        else:
            tone = sine(f, dur) + 0.3 * sine(f * 2, dur)
        place(out, tone * decay(N(dur), 6), i * step, gain)
    return out


def make_items():
    save("loot_pickup", sweep(500, 950, 0.1) * decay(N(0.1), 28) + sine(1400, 0.1) * decay(N(0.1), 40) * 0.3)
    rattle = np.zeros(N(0.35))
    for i in range(5):
        place(rattle, sine(RNG.uniform(1800, 3200), 0.04) * decay(N(0.04), 90) + hp(noise(0.03), 3000) * decay(N(0.03), 120) * 0.5, i * 0.045 + RNG.uniform(0, 0.02), 0.6)
    save("ammo_pickup", rattle)
    save("ui_click", sine(1100, 0.05) * decay(N(0.05), 70) + sine(1650, 0.05) * decay(N(0.05), 90) * 0.4)
    save("ui_slot", sine(700, 0.06) * decay(N(0.06), 55) * 0.8 + hp(noise(0.03), 2500) * decay(N(0.03), 120) * 0.3)
    save("ui_error", square(160, 0.2) * decay(N(0.2), 8) * 0.4 + square(120, 0.2) * decay(N(0.2), 8) * 0.3)
    # chest creak + thump + chime
    n = N(0.7)
    vib = 200 + 60 * np.sin(np.linspace(0, 18, n)) + np.linspace(0, 120, n)
    creak = bp(saw(vib, 0.7), 250, 1800) * np.sin(np.linspace(0, np.pi, n)) ** 0.7 * 1.2
    thump = _pad(lp(noise(0.18), 500) * decay(N(0.18), 24) + sine(85, 0.18) * decay(N(0.18), 20) * 0.9, (N(0.55), 0))
    save("chest_open", mix(creak * 0.7, thump))
    save("ammo_box_open", mix(hp(noise(0.12), 600) * decay(N(0.12), 40) + sine(520, 0.12) * decay(N(0.12), 30) * 0.5, _pad(lp(noise(0.2), 600) * decay(N(0.2), 24) + sine(95, 0.2) * decay(N(0.2), 20), (N(0.25), 0))))
    # rarity chimes: more notes + brighter as the tier rises
    save("rarity_1", chime([72, 76], 0.08, 0.4))
    save("rarity_2", chime([72, 76, 79], 0.08, 0.5))
    save("rarity_3", chime([72, 76, 79, 84], 0.08, 0.6))
    save("rarity_4", chime([69, 72, 76, 81, 84], 0.08, 0.8) + 0.0)
    save("rarity_5", chime([64, 67, 71, 76, 79, 83, 88], 0.07, 1.0))
    # mythic: low boom, rising shimmer, chord
    myth = np.zeros(N(2.4))
    place(myth, sweep(70, 35, 1.2) * decay(N(1.2), 3.5) * 0.9, 0.0)
    place(myth, sweep(300, 1800, 1.2, 1.8) * decay(N(1.2), 1.5) * 0.4, 0.0)
    for i, m in enumerate([57, 64, 69, 76, 81]):
        place(myth, (sine(midi(m), 1.6) + 0.3 * sine(midi(m) * 2.01, 1.6)) * decay(N(1.6), 2.2), 0.45 + i * 0.1, 0.35)
    save("rarity_6", reverb(myth, 0.3, 1.4, 1.0))
    # consumables
    save("consume_bandage", bp(noise(0.9), 1500, 5000) * (0.5 + 0.5 * np.abs(np.sin(np.linspace(0, 9 * np.pi, N(0.9))))) * 0.7)
    gl = np.zeros(N(1.0))
    for i in range(7):
        f0 = RNG.uniform(250, 500)
        place(gl, sweep(f0, f0 * 1.8, 0.09) * decay(N(0.09), 30), i * 0.12 + RNG.uniform(0, 0.03), 0.6)
    save("consume_potion", gl)
    save("shield_up", mix(sweep(400, 1600, 0.5, 1.5) * decay(N(0.5), 4) * 0.5, chime([76, 83, 88], 0.09, 0.5, gain=0.4)))
    save("heal_up", chime([60, 64, 67, 72], 0.1, 0.8, wave="soft", gain=0.45))


# ----------------------------------------------------------------------------- world

def make_build():
    save("build_place", lp(noise(0.22), 900) * decay(N(0.22), 22) + sine(150, 0.22) * decay(N(0.22), 20) * 0.8 + bp(noise(0.12), 2000, 6000) * decay(N(0.12), 60) * 0.35)
    crush = bp(noise(0.7), 150, 3500) * decay(N(0.7), 6) + lp(noise(0.7), 400) * decay(N(0.7), 5) * 0.8
    for i in range(6):
        place(crush, hp(noise(0.05), 1200) * decay(N(0.05), 80), RNG.uniform(0.02, 0.4), 0.5)
    save("build_break", crush + sine(70, 0.7) * decay(N(0.7), 7) * 0.5)
    save("build_toggle", bp(noise(0.25), 400, 3500) * np.sin(np.linspace(0, np.pi, N(0.25))) ** 1.2 * 0.8 + sine(np.linspace(300, 700, N(0.25)), 0.25) * decay(N(0.25), 10) * 0.25)


def make_world():
    # bus engine drone + propeller thump (seamless 3 s)
    L = 3.0
    base = 62.0
    t = np.arange(N(L)) / SR
    drone = np.sin(2 * np.pi * base * t) + 0.5 * np.sin(2 * np.pi * base * 2 * t) + 0.3 * np.sin(2 * np.pi * base * 3 * t)
    thump = (np.sin(2 * np.pi * 14 * t) > 0.6) * 0.3
    save("bus_loop", lp(drone, 400) * 0.5 + lp(noise(L), 700) * 0.35 + lp(thump, 120) * 0.8)
    # wind (freefall) and glider (soft)
    L = 3.0
    wind = bp(noise(L), 300, 3500) * (0.8 + 0.2 * np.sin(2 * np.pi * np.arange(N(L)) / SR / L * 4))
    save("wind_loop", wind)
    save("glider_loop", lp(noise(L), 1200) * 0.5 * (0.8 + 0.2 * np.sin(2 * np.pi * np.arange(N(L)) / SR / L * 2)))
    save("glider_open", mix(bp(noise(0.55), 200, 1800) * np.sin(np.linspace(0, np.pi, N(0.55))) ** 0.8 * 0.9, _pad(lp(noise(0.2), 400) * decay(N(0.2), 20) + sine(70, 0.2) * decay(N(0.2), 18) * 0.6, (N(0.18), 0))))
    # storm: low rumble with crackle (seamless 6 s)
    L = 6.0
    t = np.arange(N(L)) / SR
    rumble = lp(noise(L), 160) * (0.7 + 0.3 * np.sin(2 * np.pi * t / L * 2)) * 2.0
    crack = np.zeros(N(L))
    for i in range(24):
        place(crack, hp(noise(0.05), 2500) * decay(N(0.05), 90), RNG.uniform(0, L - 0.1), RNG.uniform(0.1, 0.35))
    shimmer = sine(110 + 6 * np.sin(2 * np.pi * t / L * 3), L) * 0.2
    save("storm_loop", rumble + crack + shimmer)
    # warning siren
    siren = np.zeros(N(1.6))
    for i in range(2):
        place(siren, (square(np.linspace(420, 620, N(0.7)), 0.7) * 0.4 + sweep(420, 620, 0.7) * 0.6) * np.sin(np.linspace(0, np.pi, N(0.7))) ** 0.5, i * 0.78)
    save("storm_warn", lp(siren, 2500))
    save("storm_hit", hp(noise(0.12), 1500) * decay(N(0.12), 40) + sweep(900, 120, 0.12) * decay(N(0.12), 25) * 0.7)
    # ambient wind (6 s) and birds
    L = 6.0
    t = np.arange(N(L)) / SR
    amb = bp(noise(L), 120, 1800) * (0.35 + 0.25 * np.sin(2 * np.pi * t / L * 2) ** 2)
    save("ambient_loop", amb)
    for i in range(3):
        b = np.zeros(N(0.7))
        base = RNG.uniform(2200, 3800)
        for j in range(RNG.integers(2, 5)):
            f = np.linspace(base, base * RNG.uniform(1.15, 1.5), N(0.09))
            place(b, sine(f, 0.09) * np.sin(np.linspace(0, np.pi, N(0.09))), j * 0.12, 0.5)
        save("bird_%d" % (i + 1), b)
    # vehicles
    L = 2.0
    t = np.arange(N(L)) / SR
    car = sum(np.sin(2 * np.pi * 48 * k * t) / k for k in range(1, 7)) * (0.8 + 0.2 * np.sin(2 * np.pi * 24 * t))
    save("engine_car_loop", lp(car, 800) * 0.6 + lp(noise(L), 500) * 0.15)
    quad = sum(np.sin(2 * np.pi * 95 * k * t) / (k ** 0.8) for k in range(1, 8)) * (0.85 + 0.15 * np.sin(2 * np.pi * 47 * t))
    save("engine_quad_loop", lp(quad, 2200) * 0.5 + bp(noise(L), 600, 3000) * 0.12)
    boat = lp(noise(L), 350) * (0.7 + 0.3 * np.sin(2 * np.pi * 36 * t)) * 1.4 + np.sin(2 * np.pi * 36 * t) * 0.3
    save("engine_boat_loop", boat + bp(noise(L), 700, 2500) * 0.15)
    horn = (square(392, 0.55) + square(494, 0.55)) * 0.25
    save("car_horn", lp(horn, 2500) * np.minimum(1, np.linspace(0, 40, N(0.55))) * np.minimum(1, np.linspace(10, 0, N(0.55))))
    save("door", lp(noise(0.2), 800) * decay(N(0.2), 25) + sine(120, 0.2) * decay(N(0.2), 25) * 0.8 + hp(noise(0.05), 1500) * decay(N(0.05), 100) * 0.3)
    save("vehicle_crash", lp(noise(0.5), 1200) * decay(N(0.5), 10) + sine(70, 0.5) * decay(N(0.5), 9) * 0.9 + sine(1100, 0.5) * decay(N(0.5), 12) * 0.2 + hp(noise(0.5), 2500) * decay(N(0.5), 40) * 0.3)
    save("skid", bp(noise(0.8), 1200, 4000) * np.sin(np.linspace(0, np.pi, N(0.8))) ** 0.5 * 0.5)
    boom = lp(noise(1.6), 600) * decay(N(1.6), 3.2) + sweep(120, 28, 1.6, 0.4) * decay(N(1.6), 2.2) * 1.2 + hp(noise(0.3), 1500) * decay(N(0.3), 15) * 0.5
    save("explosion", reverb(boom, 0.25, 1.5, 1.2))


# ----------------------------------------------------------------------------- music

def pluck(f, dur, bright=1.0):
    n = N(dur)
    return (sine(f, dur) + 0.35 * bright * sine(f * 2, dur) * decay(n, 10) + 0.12 * bright * sine(f * 3, dur) * decay(n, 16)) * decay(n, 6)


def pad_voice(f, dur, attack=0.4, release=0.5):
    n = N(dur)
    v = (saw(f * 0.996, dur) + saw(f * 1.004, dur) + saw(f * 2.0, dur) * 0.3) * 0.33
    v = lp(v, 1400)
    env = np.minimum(1, np.arange(n) / SR / attack) * np.minimum(1, (n - np.arange(n)) / SR / release)
    return v * env


def bell(f, dur):
    n = N(dur)
    return (sine(f, dur) + 0.5 * sine(f * 2.76, dur) * decay(n, 6) + 0.25 * sine(f * 5.4, dur) * decay(n, 10)) * decay(n, 3.2)


def kick():
    return fit(sweep(150, 45, 0.18, 0.5), N(0.2)) * decay(N(0.2), 14) * 1.2


def hat(open_=False):
    d = 0.18 if open_ else 0.05
    return hp(noise(d), 6000) * decay(N(d), 25 if open_ else 90) * 0.25


def snare():
    return bp(noise(0.2), 1500, 6000) * decay(N(0.2), 22) * 0.6 + sine(190, 0.2) * decay(N(0.2), 24) * 0.5


def compose(name, bpm, bars, progression, root, minor, drums=False, melody=None, arp="eighth", pad_gain=0.5, bass_gain=0.5, arp_gain=0.35, mel_gain=0.4, swing=0.0):
    beat = 60.0 / bpm
    bar = beat * 4
    L = bar * bars
    total = np.zeros(N(L + 4.0))
    third = 3 if minor else 4
    for b in range(bars):
        deg = progression[b % len(progression)]
        r = root + deg
        chord = [r, r + third, r + 7, r + 12]
        t0 = b * bar
        for k, m in enumerate(chord[:3]):
            place(total, pad_voice(midi(m), bar + 0.8, 0.5, 0.7), t0, pad_gain * 0.45)
        # bass: root on beats 1 and 3
        for q in (0, 2):
            place(total, fit(sine(midi(r - 12), beat * 1.9) * decay(N(beat * 1.9), 2.5), N(beat * 1.9)), t0 + q * beat, bass_gain)
        # arpeggio
        steps = 8 if arp == "eighth" else 16
        pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        for s in range(steps):
            m = chord[pattern[s % len(pattern)]] + (12 if (s % 4 == 3) else 0)
            place(total, pluck(midi(m + 12), beat * 0.9), t0 + s * (bar / steps), arp_gain * (0.6 + 0.4 * (s % 2 == 0)))
        if drums:
            for q in range(4):
                place(total, kick(), t0 + q * beat, 0.9)
                place(total, hat(False), t0 + q * beat + beat / 2, 0.7)
            place(total, snare(), t0 + beat, 0.7)
            place(total, snare(), t0 + 3 * beat, 0.7)
            place(total, hat(True), t0 + 3.5 * beat, 0.5)
        if melody:
            for (beat_pos, deg_off, dur_b) in melody[b % len(melody)] if isinstance(melody[0], list) else []:
                place(total, bell(midi(r + deg_off + 24), dur_b * beat), t0 + beat_pos * beat, mel_gain)
    total = reverb(total, 0.22, 1.6, 1.5)
    save(name, loopify(total, L), 0.8)


def stinger(name, notes, step, dur, minor=False, boom=False):
    out = np.zeros(N(step * len(notes) + dur + 1.0))
    for i, m in enumerate(notes):
        place(out, bell(midi(m), dur) + pad_voice(midi(m - 12), dur, 0.05, 0.6) * 0.5, i * step, 0.5)
    if boom:
        place(out, sweep(90, 40, 0.9, 0.6) * decay(N(0.9), 3) * 0.9, 0.0)
    save(name, reverb(out, 0.3, 1.5, 1.2), 0.85)


def make_music():
    # calm & hopeful (menu): C major
    compose("music_menu", 92, 16, [0, 7, 9, 5], 48, False, drums=False, arp="eighth", pad_gain=0.6, arp_gain=0.30,
            melody=[[(0, 4, 1.5), (2, 7, 1.0), (3, 9, 1.0)], [(0, 7, 2.0), (2, 4, 2.0)], [(0, 9, 1.5), (2, 7, 1.0), (3, 4, 1.0)], [(0, 5, 3.0)]])
    # energetic (battle bus): E minor, drums
    compose("music_bus", 118, 16, [0, 8, 3, 10], 52, True, drums=True, arp="sixteenth", pad_gain=0.45, arp_gain=0.28, bass_gain=0.65,
            melody=[[(0, 12, 1.0), (1.5, 15, 0.5), (2, 14, 1.0), (3, 10, 1.0)], [(0, 12, 2.0), (2, 7, 1.0), (3, 10, 1.0)]])
    # tense ambient (in game): A minor, slow, sparse
    compose("music_game", 76, 14, [0, 8, 3, 7], 45, True, drums=False, arp="eighth", pad_gain=0.7, arp_gain=0.2, bass_gain=0.55,
            melody=[[(0, 12, 3.0), (3, 10, 1.0)], [(0, 7, 2.0), (2, 8, 2.0)], [(0, 15, 3.0)], [(0, 10, 4.0)]])
    # combat: faster, drums
    compose("music_combat", 132, 16, [0, 0, 8, 7], 45, True, drums=True, arp="sixteenth", pad_gain=0.4, arp_gain=0.3, bass_gain=0.7)
    stinger("music_victory", [60, 64, 67, 72, 76, 79], 0.14, 2.2)
    stinger("music_defeat", [64, 62, 60, 57], 0.35, 2.2, minor=True, boom=True)


def main():
    print("writing", OUT)
    make_weapons()
    make_movement()
    make_items()
    make_world()
    make_build()
    make_music()


if __name__ == "__main__":
    main()
