#!/usr/bin/env python3
"""Synthesise the boss-character sounds: Drum Gun, Shockwave Launcher, Grappler, Charge Shotgun charge, boss stingers.

    python3 tools/audio/generate_boss_sfx.py                  # write every sound + its .wav.import
    python3 tools/audio/generate_boss_sfx.py shot_drum_gun    # just one
    python3 tools/audio/generate_boss_sfx.py --verify         # measure the files on disk
    python3 tools/audio/generate_boss_sfx.py --list

Needs numpy only, deterministic, no network, no API. Reuses the building blocks of generate_storm_island_sfx.py.
Output: mono, 44100 Hz, 16-bit PCM WAV, sample peak -3 dBFS, exact length, 1 ms fade-in on one-shots.
grappler_pull is built from a periodic phase and circular filtering with no fades, so it repeats without a click
(Audio.gd only auto-loops names ending in _loop, so the code has to loop this one itself).
The boss stingers are instrumental only (synth horn, brass, plucks, chimes): no voice.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_storm_island_sfx import (OUT, PEAK_DB, SR, bq, finish, harmonics, metal_hit, noise, periodic, put,  # noqa: E402
                                       ramp, read_wav, reverb, smooth, tt, write_import, write_wav, _pad)
from generate_weapon_extras_sfx import click, fit, mp, sweep_sine  # noqa: E402

MAX_LEAD_S = 0.05
MAX_TAIL_S = 0.5


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def env_ad(n, a, d_tau):
    t = tt(n)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / d_tau)


def trim_lead(y, keep=0.003):
    """Drop leading near-silence (< -60 dB of the peak) so the sound starts at once."""
    nz = np.nonzero(np.abs(y) >= np.max(np.abs(y)) * 10 ** (-60 / 20))[0]
    return y[max(0, nz[0] - int(keep * SR)):]


def thump(n, f0, f1, tau, dec):
    return sweep_sine(f0, f1, n, tau) * np.exp(-tt(n) / dec)


def crackle(rng, n, density, lo=2500, hi=9000, shape=None):
    """Electric crackle: random sparse clicks, density in clicks/s (array or float), each a tiny band-passed tick."""
    t = tt(n)
    dens = np.full(n, float(density)) if np.isscalar(density) else density
    hits = rng.random(n) < dens / SR
    imp = hits * rng.uniform(0.3, 1.0, n) * rng.choice([-1.0, 1.0], n)
    y = bq(imp, "bp", math.sqrt(lo * hi), 0.7) * 6
    y += bq(imp, "hp", hi * 0.5) * 3
    return y * (1.0 if shape is None else shape)


def pluck(f, dur, seed, damp=0.4965, bright=1.0):
    """Karplus-Strong string."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    p = max(2, int(round(SR / f)))
    buf = rng.uniform(-1, 1, p) * bright
    buf -= np.mean(buf)
    out = np.empty(n)
    for i in range(n):
        j = i % p
        out[i] = buf[j]
        buf[j] = damp * (buf[j] + buf[(j + 1) % p])
    return out


# ------------------------------------------------------------------ weapons

def shot_drum_gun():
    rng = np.random.default_rng(401)
    n = int(0.12 * SR)
    t = tt(n)
    crack = bq(noise(rng, n), "bp", 2600, 0.6) * np.exp(-t / 0.005) * 1.0
    boom = bq(noise(rng, n), "lp", 800) * np.exp(-t / 0.024) * 0.9                       # a bit boomy
    low = thump(n, 190, 70, 0.02, 0.035) * 0.9
    gold = fit(metal_hit(2600, 0.1, 11, 0.5), n) * 0.16                                   # gold-plated ping
    y = (crack + boom + low + gold) * ramp(n, 0.0004)
    y = y + reverb(y, 0.08, 5000, 401, pre=0.002, length=0.06) * 0.25                  # tiny tail
    return finish(y, 0.12, fade_out=0.04)


def reload_drum_gun():
    rng = np.random.default_rng(402)
    n = int(2.0 * SR)
    y = np.zeros(n)
    # drum twisted out: ratchet clicks, a latch, a short grind
    for k in range(7):
        put(y, 0.08 + 0.035 * k, click(rng, 2300 - 120 * k, 0.005, 0.5))
    put(y, 0.05, bq(noise(rng, int(0.3 * SR)), "bp", 900, 0.8) * np.hanning(int(0.3 * SR)), 0.25)
    put(y, 0.34, mp(click(rng, 1400, 0.01, 0.7), metal_hit(800, 0.12, 12, 0.4) * 0.5))
    # rattling drum of bullets: lots of small ticks, swelling then dying away
    for k in range(70):
        t0 = 0.55 + 0.75 * rng.random()
        g = math.sin(math.pi * (t0 - 0.55) / 0.75) ** 0.6 * rng.uniform(0.2, 0.7)
        put(y, t0, mp(metal_hit(rng.uniform(2800, 5200), 0.05, 100 + k, 0.6) * 0.5, click(rng, 3000, 0.004, 0.3)), g)
    put(y, 0.55, bq(noise(rng, int(0.75 * SR)), "bp", 1800, 0.6) * np.hanning(int(0.75 * SR)), 0.12)
    # slapped back in: thud and clack
    put(y, 1.38, thump(int(0.12 * SR), 200, 80, 0.02, 0.035) * 1.1)
    put(y, 1.38, mp(click(rng, 1800, 0.012, 1.0), metal_hit(1100, 0.15, 13, 0.5) * 0.6))
    # bolt rack
    put(y, 1.62, mp(click(rng, 1600, 0.01, 0.8), metal_hit(1400, 0.1, 14, 0.5) * 0.4))
    put(y, 1.64, bq(noise(rng, int(0.1 * SR)), "bp", 1100, 0.8) * np.hanning(int(0.1 * SR)), 0.2)
    put(y, 1.8, mp(click(rng, 2400, 0.008, 1.0), metal_hit(2000, 0.1, 15, 0.5) * 0.5))
    return finish(trim_lead(y + reverb(y, 0.2, 5000, 402, pre=0.003, length=0.2) * 0.2), 2.0, fade_out=0.1)


def shot_shockwave_launcher():
    rng = np.random.default_rng(403)
    n = int(0.8 * SR)
    t = tt(n)
    whump = thump(n, 120, 38, 0.07, 0.22) * 1.0                                         # pressure "whump"
    air = bq(noise(rng, n), "lp", 500) * np.exp(-t / 0.08) * 0.7
    # rising electric zap: gliding saw through a rising band-pass, with a jitter
    f = 350 * (4200 / 350) ** smooth(t / 0.6)
    ph = np.cumsum(f) / SR
    zap = harmonics(ph, 10, 1.0, odd=True) * (0.6 + 0.4 * np.sin(2 * math.pi * 55 * t))
    zap *= np.minimum(t / 0.04, 1.0) * np.where(t < 0.55, 1.0, np.exp(-(t - 0.55) / 0.07)) * 0.45
    crk = crackle(rng, n, 500 * smooth(t / 0.6) + 40, 3000, 8000) * 0.5 * (t < 0.65)
    y = (whump + air + zap + crk) * ramp(n, 0.0008)
    y = y + reverb(y, 0.35, 3000, 403, pre=0.004, length=0.4) * 0.3
    return finish(y, 0.8, fade_out=0.12)


def shockwave_blast():
    rng = np.random.default_rng(404)
    n = int(1.2 * SR)
    t = tt(n)
    boom = thump(n, 85, 27, 0.12, 0.34) * 1.3                                           # sub-bass boom
    crack = bq(noise(rng, n), "bp", 3800, 0.5) * np.exp(-t / 0.006) * 1.4              # sharp air crack
    wave_ = bq(noise(rng, n), "lp", 1200) * np.exp(-t / 0.09) * 0.8
    sweepn = bq(noise(rng, n), "bp", 700, 0.8) * smooth(t / 0.04) * np.exp(-t / 0.22) * 0.7   # air rushing outward
    crk = crackle(rng, n, 380 * np.exp(-t / 0.35) + 10, 2500, 9000) * 0.55 * smooth(t / 0.02)  # fading electric crackle
    y = (boom + crack + wave_ + sweepn + crk) * ramp(n, 0.0005)
    y = y + reverb(y, 0.7, 2500, 404, pre=0.008, length=0.8) * 0.4
    return finish(y, 1.2, fade_out=0.25)


def reload_shockwave_launcher():
    rng = np.random.default_rng(405)
    n = int(1.8 * SR)
    t = tt(n)
    y = np.zeros(n)
    # heavy cartridge slides in: scrape, then a deep clunk
    sl = int(0.32 * SR)
    put(y, 0.05, bq(noise(rng, sl), "bp", 700, 0.7) * np.hanning(sl) * (0.6 + 0.4 * np.sin(2 * math.pi * 45 * tt(sl))), 0.45)
    put(y, 0.40, thump(int(0.2 * SR), 130, 55, 0.03, 0.06) * 1.1)
    put(y, 0.40, mp(click(rng, 1200, 0.012, 1.0), metal_hit(520, 0.25, 16, 0.5) * 0.55))
    put(y, 0.52, mp(click(rng, 2200, 0.008, 0.7), metal_hit(1600, 0.1, 17, 0.5) * 0.3))      # breech latch
    # coils charge up: rising hum with a growing shimmer
    s = np.clip((t - 0.6) / 1.15, 0, 1)
    f = 80 * (520 / 80) ** s
    hum = harmonics(np.cumsum(f) / SR, 8, 1.2) * (0.5 + 0.5 * np.sin(2 * math.pi * 14 * t))
    hum2 = np.sin(2 * math.pi * np.cumsum(f * 2.01) / SR) * 0.4
    amp = smooth((t - 0.6) / 0.5) * (0.5 + 0.5 * s) * np.where(t < 1.72, 1.0, np.exp(-(t - 1.72) / 0.03))
    y += (hum + hum2) * amp * 0.9
    y += crackle(rng, n, 220 * s + 5, 3000, 9000) * 0.3 * (t > 0.6) * amp
    put(y, 1.72, mp(click(rng, 3200, 0.008, 0.8), metal_hit(2700, 0.1, 18, 0.5) * 0.25))    # "ready" tick
    return finish(trim_lead(y + reverb(y, 0.25, 4000, 405, pre=0.003, length=0.25) * 0.2), 1.8, fade_out=0.08)


# ------------------------------------------------------------------ grappler

def grappler_fire():
    rng = np.random.default_rng(406)
    n = int(0.5 * SR)
    t = tt(n)
    thwip = bq(noise(rng, n), "bp", 1700, 0.9) * np.exp(-t / 0.014) * 1.2               # pneumatic pop
    puff = bq(noise(rng, n), "lp", 900) * np.exp(-t / 0.03) * 0.7
    body = thump(n, 260, 90, 0.015, 0.03) * 0.7
    sw = bq(noise(rng, n), "bp", 2500, 1.2) * smooth(t / 0.01) * np.exp(-t / 0.05) * 0.5
    zf = 3000 + 2600 * smooth(t / 0.25)                                                  # cable zing, rising
    zing = (np.sin(2 * math.pi * np.cumsum(zf) / SR) + 0.4 * np.sin(2 * math.pi * np.cumsum(zf * 1.52) / SR))
    zing *= (1 + 0.15 * np.sin(2 * math.pi * 60 * t)) * np.exp(-t / 0.09) * smooth(t / 0.015) * 0.22
    y = (thwip + puff + body + sw + zing) * ramp(n, 0.0005)
    return finish(y, 0.5, fade_out=0.15)


def grappler_hit():
    rng = np.random.default_rng(407)
    n = int(0.3 * SR)
    t = tt(n)
    y = fit(metal_hit(1050, 0.28, 19, 1.0), n) * 0.8 + fit(metal_hit(1900, 0.15, 20, 0.8), n) * 0.4   # clank
    y = mp(y, click(rng, 2200, 0.006, 1.0))
    y = y[:n]
    scr = bq(noise(rng, n), "bp", 2400, 0.9) * (0.5 + 0.5 * np.sign(np.sin(2 * math.pi * 95 * t))) * smooth((t - 0.03) / 0.01)
    scr *= np.exp(-np.maximum(t - 0.04, 0) / 0.05) * 0.5                                    # short scrape
    y = (y + scr + thump(n, 180, 80, 0.015, 0.03) * 0.5) * ramp(n, 0.0003)
    return finish(y, 0.3, fade_out=0.1)


def grappler_pull():
    """1.0 s seamless loop: whine with a periodic pitch swell, gear tick and rope creak (all integer cycles)."""
    rng = np.random.default_rng(408)
    n = SR
    t = tt(n)
    ph = 780 * t + (170 / (2 * math.pi)) * (1 - np.cos(2 * math.pi * t))                  # integer cycles over 1.0 s
    whine = np.sin(2 * math.pi * ph) + 0.35 * np.sin(4 * math.pi * ph) + 0.15 * np.sin(6 * math.pi * ph)
    gear = harmonics(96 * t, 12, 0.8) * 0.18                                               # 96 Hz motor/gear rumble
    creak_env = 0.5 + 0.5 * np.sign(np.sin(2 * math.pi * 14 * t + 1.0 * np.sin(2 * math.pi * t)))
    creak = periodic(noise(rng, n), lambda x: bq(x, "bp", 520, 2.5)) * creak_env * 0.9      # rope creak
    rope = periodic(noise(rng, n), lambda x: bq(x, "bp", 1500, 0.9)) * (0.4 + 0.6 * np.abs(np.sin(2 * math.pi * 7 * t))) * 0.25
    y = whine * 0.55 + gear + creak * 0.55 + rope
    y = periodic(y, lambda x: bq(x, "lp", 6500))
    return finish(y, 1.0, loop=True)


def grappler_release():
    rng = np.random.default_rng(409)
    n = int(0.3 * SR)
    t = tt(n)
    y = bq(noise(rng, n), "lp", 1800) * np.exp(-t / 0.05) * smooth(t / 0.01) * 0.5          # cable going slack
    for k, (t0, g) in enumerate([(0.0, 0.8), (0.045, 0.6), (0.095, 0.45), (0.15, 0.3), (0.215, 0.2)]):
        put(y, t0, mp(metal_hit(rng.uniform(1800, 3200), 0.07, 30 + k, 0.7) * 0.5, click(rng, 2600, 0.004, 0.4)), g)
    return finish(y * ramp(n, 0.0005), 0.3, fade_out=0.12)


def charge_shotgun_charge():
    rng = np.random.default_rng(410)
    n = int(1.8 * SR)
    t = tt(n)
    s = (t / 1.8)
    f = 70 * (950 / 70) ** (s ** 1.4)                                                       # rising hum, peaks at 1.8 s
    ph = np.cumsum(f) / SR
    hum = harmonics(ph, 10, 1.0, odd=True) * (0.55 + 0.45 * np.sin(2 * math.pi * (6 + 18 * s) * t))
    sub = np.sin(2 * math.pi * np.cumsum(f * 0.5) / SR) * 0.4
    zz = bq(noise(rng, n), "bp", 2500, 0.8) * s ** 2 * 0.3                                  # growing electric hiss
    crk = crackle(rng, n, 30 + 700 * s ** 2, 2500, 9000) * 0.5 * s
    y = (hum * 0.7 + sub + zz + crk) * (0.08 + 0.92 * s ** 1.6)
    return finish(y, 1.8, fade_out=0.012)


# ------------------------------------------------------------------ bosses (instrumental only)

def boss_voltra_intro():
    rng = np.random.default_rng(411)
    n = int(2.5 * SR)
    t = tt(n)
    amp = smooth(t / 0.6) * np.where(t < 1.9, 1.0, np.exp(-(t - 1.9) / 0.22))
    horn = np.zeros(n)
    for f0, g in [(55.0, 1.0), (82.4, 0.6), (110.0, 0.45)]:                                 # ominous low horn: root, fifth, octave
        for det in (-0.006, 0.006):
            horn += g * harmonics(np.cumsum(f0 * (1 + det) * (1 + 0.004 * np.sin(2 * math.pi * 4.5 * t))) / SR, 18, 1.0) / 2
    dark = bq(horn, "lp", 380)
    bright = bq(horn, "lp", 1800)
    sw = smooth((t - 0.2) / 1.5)
    horn = (dark * (1 - sw) + bright * sw) * amp
    grow = smooth(t / 2.0)
    crk = crackle(rng, n, 25 + 260 * grow, 2200, 9000) * (0.25 + 0.75 * grow) * 0.6 * np.where(t < 2.1, 1.0, np.exp(-(t - 2.1) / 0.12))
    buzz = bq(noise(rng, n), "bp", 3000, 1.0) * (0.5 + 0.5 * np.sign(np.sin(2 * math.pi * 100 * t))) * grow * 0.07 * amp
    sub = thump(n, 90, 40, 0.1, 0.5) * 0.7
    y = horn * 0.8 + crk + buzz + sub * (t < 1.0)
    y = y + reverb(y, 1.1, 2500, 411, pre=0.015, length=1.2) * 0.4
    return finish(y, 2.5, fade_out=0.25)


def _brass(f, dur, n, t0_amp=0.05, bright=1.0):
    tt_ = tt(n)
    ph = np.cumsum(np.full(n, f) * (1 + 0.003 * np.sin(2 * math.pi * 5.2 * tt_ + 0.7))) / SR
    y = harmonics(ph, 14, 0.9)
    open_ = smooth(tt_ / 0.12)
    return bq(y, "lp", 900 + 2800 * open_[-1] * bright) * ramp(n, t0_amp) * 1.0


def boss_goldhand_intro():
    rng = np.random.default_rng(412)
    n = int(2.5 * SR)
    t = tt(n)
    y = np.zeros(n)
    # regal fanfare: G3 - B3 - D4 pickup notes, then a long G major chord
    for t0, notes, dur, g in [(0.0, [55], 0.36, 0.7), (0.3, [59], 0.36, 0.75), (0.6, [62], 0.36, 0.8),
                              (0.95, [43, 55, 59, 62, 67], 1.3, 1.0)]:
        m = int(dur * SR) + int(0.25 * SR)
        seg = np.zeros(m)
        for k, nm in enumerate(notes):
            seg += _brass(midi(nm + 12 - 12), dur, m, 0.045) * (1.3 if k == 0 and len(notes) > 1 else 1.0)
        e = np.minimum(np.arange(m) / (0.04 * SR), 1.0) * np.where(np.arange(m) < dur * SR, 1.0, np.exp(-(np.arange(m) - dur * SR) / (0.09 * SR)))
        put(y, t0, seg * e, g / max(1, len(notes)) ** 0.5)
    # coin-chime shimmer
    for k in range(18):
        t0 = 1.0 + 1.1 * rng.random() ** 1.3
        f = rng.choice([midi(91), midi(95), midi(98), midi(103), midi(107)])
        m = int(0.5 * SR)
        tm = tt(m)
        chime = (np.sin(2 * math.pi * f * tm) + 0.4 * np.sin(2 * math.pi * f * 2.76 * tm) * np.exp(-tm / 0.05)) * np.exp(-tm / 0.15)
        put(y, t0, chime, rng.uniform(0.1, 0.22))
    put(y, 0.95, thump(int(0.5 * SR), 110, 45, 0.05, 0.12) * 0.7)
    y = y + reverb(y, 1.3, 4500, 412, pre=0.02, length=1.4) * 0.45
    return finish(y, 2.5, fade_out=0.35)


def boss_hookshot_intro():
    rng = np.random.default_rng(413)
    n = int(2.5 * SR)
    t = tt(n)
    y = np.zeros(n)
    # sneaky, tense plucked line: A3 Bb3 A3 E4 (tritone-ish creep), then a low held pluck
    for t0, m_, g in [(0.0, 57, 0.8), (0.28, 58, 0.7), (0.56, 57, 0.8), (0.84, 64, 0.65), (1.2, 63, 0.6), (1.5, 45, 1.0)]:
        p = pluck(midi(m_), 0.9, 500 + m_)
        put(y, t0, p * np.exp(-tt(len(p)) / 0.55), g)
    # rope creak: pulsing bandpassed noise whose centre drifts
    creak_n = int(1.3 * SR)
    ct = tt(creak_n)
    cr = bq(noise(rng, creak_n), "bp", 480, 2.5) * (0.5 + 0.5 * np.sign(np.sin(2 * math.pi * 13 * ct + 2 * np.sin(2 * math.pi * 1.1 * ct))))
    cr += bq(noise(rng, creak_n), "bp", 1100, 3.0) * (0.5 + 0.5 * np.sign(np.sin(2 * math.pi * 9 * ct))) * 0.5
    put(y, 0.4, cr * np.hanning(creak_n) * 0.5)
    # short whoosh near the end
    wn = int(0.35 * SR)
    wt = tt(wn)
    wh = bq(noise(rng, wn), "bp", 900, 0.7) * np.sin(np.pi * np.linspace(0, 1, wn)) ** 2
    wh2 = bq(noise(rng, wn), "bp", 2600, 0.8) * np.sin(np.pi * np.linspace(0, 1, wn)) ** 3 * 0.5
    put(y, 1.75, wh + wh2, 0.6)
    y = y + reverb(y, 0.7, 3500, 413, pre=0.01, length=0.8) * 0.35
    return finish(y, 2.5, fade_out=0.3)


def boss_defeated():
    rng = np.random.default_rng(414)
    n = int(2.0 * SR)
    t = tt(n)
    y = np.zeros(n)
    # heavy armour drop: sub thud, metal clatter
    put(y, 0.0, thump(int(0.6 * SR), 95, 32, 0.07, 0.2) * 1.4)
    put(y, 0.0, bq(noise(rng, int(0.2 * SR)), "lp", 1200) * np.exp(-tt(int(0.2 * SR)) / 0.03) * 0.8)
    for k, (t0, base, g) in enumerate([(0.0, 520, 0.9), (0.07, 800, 0.7), (0.13, 1300, 0.55), (0.21, 640, 0.45),
                                       (0.29, 2100, 0.35), (0.38, 950, 0.3), (0.47, 1700, 0.2)]):
        put(y, t0, mp(metal_hit(base, 0.3, 40 + k, 1.0) * 0.6, click(rng, 2400, 0.005, 0.6)), g)
    # rising shimmer
    m = int(1.0 * SR)
    mt = tt(m)
    f = 500 * (3600 / 500) ** smooth(mt / 0.9)
    shim = sum(np.sin(2 * math.pi * np.cumsum(f * r) / SR) * a for r, a in [(1.0, 1.0), (1.5, 0.5), (2.0, 0.35)])
    shim *= smooth(mt / 0.5) * np.where(mt < 0.8, 1.0, np.exp(-(mt - 0.8) / 0.08)) * 0.18
    put(y, 0.5, shim)
    # bright reward chime arpeggio (mythic + keycard dropped)
    for k, m_ in enumerate([72, 76, 79, 84, 88]):
        f1 = midi(m_ + 12)
        c = int(0.9 * SR)
        ct = tt(c)
        chime = (np.sin(2 * math.pi * f1 * ct) + 0.4 * np.sin(2 * math.pi * f1 * 2.76 * ct) * np.exp(-ct / 0.1)
                 + 0.15 * np.sin(2 * math.pi * f1 * 5.4 * ct) * np.exp(-ct / 0.05)) * np.exp(-ct / 0.28)
        put(y, 1.0 + 0.075 * k, chime, 0.38 + 0.04 * k)
    y = y + reverb(y, 0.9, 5000, 414, pre=0.012, length=1.0) * 0.4
    return finish(y, 2.0, fade_out=0.3)


SOUNDS = {
    "shot_drum_gun": (shot_drum_gun, 0.12), "reload_drum_gun": (reload_drum_gun, 2.0),
    "shot_shockwave_launcher": (shot_shockwave_launcher, 0.8), "shockwave_blast": (shockwave_blast, 1.2),
    "reload_shockwave_launcher": (reload_shockwave_launcher, 1.8),
    "grappler_fire": (grappler_fire, 0.5), "grappler_hit": (grappler_hit, 0.3), "grappler_pull": (grappler_pull, 1.0),
    "grappler_release": (grappler_release, 0.3), "charge_shotgun_charge": (charge_shotgun_charge, 1.8),
    "boss_voltra_intro": (boss_voltra_intro, 2.5), "boss_goldhand_intro": (boss_goldhand_intro, 2.5),
    "boss_hookshot_intro": (boss_hookshot_intro, 2.5), "boss_defeated": (boss_defeated, 2.0),
}
LOOPS = {"grappler_pull"}
# stingers and the charge ramp end on purpose at/near a fade; a natural reverb tail below -60 dB is fine up to MAX_TAIL_S


# ------------------------------------------------------------------ verification

def verify(name):
    y, info = read_wav(os.path.join(OUT, name + ".wav"))
    want = SOUNDS[name][1]
    peak = 20 * math.log10(float(np.max(np.abs(y))) + 1e-12)
    rms = math.sqrt(float(np.mean(y * y)))
    lead, trail = _pad(y)
    loop = name in LOOPS
    checks = {"format": info == (1, 2, SR), "length": len(y) == int(round(want * SR)),
              "peak": abs(peak - PEAK_DB) <= 0.1, "audible": rms > 0.01 and bool(np.all(np.isfinite(y)))}
    seam = ref = 0.0
    if loop:
        z = np.concatenate([y[-64:], y[:64]])
        seam = float(np.max(np.abs(np.diff(z, 2))))
        ref = float(np.percentile(np.abs(np.diff(y, 2)), 99.9))
        checks["seam"] = seam <= 2.0 * ref
        checks["no_edge_gap"] = lead <= 0.01 and trail <= 0.01
    else:
        checks["lead"] = lead <= MAX_LEAD_S
        checks["tail"] = trail <= MAX_TAIL_S
        checks["ends_zero"] = abs(y[0]) < 0.01 and abs(y[-1]) < 0.01
    return dict(name=name, dur=len(y) / SR, want=want, peak=peak, rms=20 * math.log10(rms), lead=lead, trail=trail,
                seam=seam, ref=ref, loop=loop, ok=all(checks.values()), failed=[k for k, v in checks.items() if not v])


def report(rows):
    print("%-26s %7s %7s %9s %9s %8s %8s  %s" % ("file", "want s", "len s", "peak dBFS", "rms dBFS", "lead ms", "trail ms", "result"))
    for r in rows:
        extra = ("  seam d2 %.5f vs %.5f" % (r["seam"], r["ref"])) if r["loop"] else ""
        print("%-26s %7.3f %7.3f %9.2f %9.1f %8.1f %8.1f  %s%s" % (
            r["name"], r["want"], r["dur"], r["peak"], r["rms"], r["lead"] * 1000, r["trail"] * 1000,
            "PASS" if r["ok"] else "FAIL " + ",".join(r["failed"]), extra))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        for n, (_f, s) in SOUNDS.items():
            print("%-26s %.2f s" % (n, s))
        return
    names = [a for a in args if a in SOUNDS] or ([] if args else list(SOUNDS))
    if "--verify" not in sys.argv:
        for n in names:
            write_wav(os.path.join(OUT, n + ".wav"), SOUNDS[n][0]())
            write_import(n)
            print("wrote", n)
    rows = [verify(n) for n in names]
    report(rows)
    sys.exit(0 if all(r["ok"] for r in rows) else 1)


if __name__ == "__main__":
    main()
