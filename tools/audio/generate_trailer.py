#!/usr/bin/env python3
"""Epic sound design for the Storm Island trailer, timed to the picture, muxed into a new MP4.

    python3 tools/audio/generate_trailer.py [path/to/StormIsland-trailer.mp4]
    needs numpy + scipy + ffmpeg/ffprobe

Writes
    assets/audio/trailer_*.wav          the individual sounds (mono, 22050 Hz, 16-bit), one file each
    assets/audio/trailer_fx_mix.wav     all of them placed on the 50 s timeline (mono, 22050 Hz, 16-bit)
    assets/trailer/StormIsland-trailer-epic.mp4   the original picture (stream copy) + original music, ducked
                                                  under the new effects; the input video is never modified
    assets/trailer/sync_cues.txt        every cue with its timecode and the on-screen event it hits

The cue times come from analysing the video (scene cuts, frame-difference spikes, luminance flashes).
"""
import os
import subprocess
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
from generate_audio import SR, lp, hp, bp, reverb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
TRAILER = os.path.join(ROOT, "assets", "trailer")
DEFAULT_VIDEO = "/root/.claude/uploads/fbc47892-fff7-5dc5-bac6-189f942c902e/f90b41b0-StormIsland-trailer.mp4"
RNG = np.random.default_rng(5150)
DUR = 50.0


# ----------------------------------------------------------------------------- primitives

def N(sec):
    return int(round(sec * SR))


def T(sec):
    return np.arange(N(sec)) / SR


def A(x):
    return np.asarray(x, dtype=float)


def white(sec):
    return RNG.uniform(-1, 1, N(sec))


def expd(sec, rate):
    return np.exp(-T(sec) * rate)


def ramp(sec, a=0.0, b=1.0, curve=1.0):
    return a + (b - a) * np.linspace(0, 1, N(sec)) ** curve


def phase(freq):
    return 2 * np.pi * np.cumsum(freq) / SR


def svf_bp(x, fc, q=0.18):
    """State-variable band-pass whose centre frequency follows the curve `fc` (Hz, per sample)."""
    x = A(x)
    f = 2 * np.sin(np.pi * np.minimum(A(fc), SR * 0.22) / SR)
    out = np.zeros(len(x))
    low = band = 0.0
    for i in range(len(x)):
        low += f[i] * band
        high = x[i] - low - q * band
        band += f[i] * high
        out[i] = band
    return out / (np.std(out) + 1e-9)


def swell(sec, peak, rise=2.0, fall=2.0):
    """Bell-shaped amplitude curve peaking at `peak` (0..1 of the length)."""
    x = np.linspace(0, 1, N(sec))
    return np.where(x < peak, (x / max(peak, 1e-6)) ** rise, ((1 - x) / max(1 - peak, 1e-6)) ** fall)


def fin(x, a=0.003, b=0.01):
    x = A(x).copy()
    na, nb = min(N(a), len(x)), min(N(b), len(x))
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def tail_off(x, sec):
    """Force a smooth fade to silence over the last `sec` seconds."""
    x = A(x).copy()
    n = min(N(sec), len(x))
    x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def stack(freqs, sec, detune=0.004, kind="saw"):
    out = np.zeros(N(sec))
    for f in freqs:
        for d in (-detune, 0, detune):
            ph = (np.cumsum(np.full(N(sec), f * (1 + d))) / SR + RNG.uniform()) % 1.0
            out += (2 * ph - 1) if kind == "saw" else np.sin(2 * np.pi * ph)
    return out / (3 * len(freqs))


def boom(sec, f0=95, f1=32, rate=2.4, drop=18):
    f = f1 + (f0 - f1) * np.exp(-T(sec) * drop)
    return np.sin(phase(f)) * expd(sec, rate)


def pad(x, sec):
    out = np.zeros(N(sec))
    out[:min(len(out), len(x))] = A(x)[:len(out)]
    return out


# ----------------------------------------------------------------------------- the sounds

def opening_rise():  # 5 s: dark swell into the title hit at 1.0 s, then a climbing tension riser into the cut at 5.0
    sec = 5.0
    t = T(sec)
    amp = np.where(t < 1.0, np.minimum(t, 1.0) ** 2.2 * 0.7, 0.12 + 0.88 * (np.maximum(t - 1.0, 0) / 4.0) ** 1.8)
    root = 55 * 2 ** (np.minimum(1, t / 5.0) * 1.0)               # A1 climbing an octave
    drone = lp(np.sin(phase(root)) + 0.5 * np.sin(phase(root * 2.0)) +
               0.35 * np.sin(phase(root * 3.0 * (1 + 0.003 * np.sin(2 * np.pi * 0.7 * t)))), 900)
    sweep_noise = svf_bp(white(sec), 250 * (14 ** (t / sec) ** 1.4), q=0.25) * (t / sec) ** 2.2
    shim = hp(white(sec), 5000) * (t / sec) ** 3 * 0.15
    hit_dip = np.where((t > 0.96) & (t < 1.5), 0.55 + 0.45 * (t - 0.96) / 0.54, 1.0)  # room for the title hit
    x = (drone * 0.9 + sweep_noise * 0.5 + shim) * amp * hit_dip
    return tail_off(x, 0.04)


def title_hit():  # 3.2 s: sub boom + crack + cymbal bloom
    sec = 3.2
    x = boom(sec, 90, 30, 1.3, 12) * 1.5 + lp(white(sec), 2500) * expd(sec, 9) * 0.9
    cym = hp(white(sec), 3500) * np.minimum(1, T(sec) / 0.12) * expd(sec, 1.7) * 0.35
    return reverb(x + cym, wet=0.4, tail=0.5)[:N(sec)]


def whoosh(sec, f0, f1, peak=0.6, q=0.25, sub=False):
    t = np.linspace(0, 1, N(sec))
    fc = np.where(t < peak, f0 * (f1 / f0) ** (t / peak), f1 * (f0 * 2 / f1) ** ((t - peak) / (1 - peak)))
    x = svf_bp(white(sec), fc, q) * swell(sec, peak, 2.0, 1.6)
    if sub:
        x += np.sin(phase(np.linspace(70, 38, N(sec)))) * swell(sec, peak, 2.5, 3.0) * 0.8
    return fin(x, 0.01, 0.02)


def whoosh_short():
    return whoosh(0.5, 400, 3600, 0.6, 0.22)


def whoosh_big():
    return whoosh(1.0, 220, 4200, 0.62, 0.25, sub=True)


def hit():  # 1.6 s taiko / trailer boom for the sub-cuts
    sec = 1.6
    x = boom(sec, 110, 42, 3.2, 20) * 1.3 + lp(white(sec), 1500) * expd(sec, 22) * 0.8 + \
        np.sin(phase(np.full(N(sec), 1.0) * 60)) * expd(sec, 5) * 0.2
    return reverb(x, wet=0.28, tail=0.4)[:N(sec)]


def dive_wind():  # 2.85 s rush of air in free fall, building until the glider opens
    sec = 2.85
    t = T(sec)
    fc = 500 + 2200 * (t / sec) ** 1.3
    gust = 1 + 0.35 * lp(white(sec), 6) / (np.std(lp(white(sec), 6)) + 1e-9) * 0.3
    x = svf_bp(white(sec), fc, 0.5) * (0.25 + 0.75 * (t / sec) ** 1.4) + hp(white(sec), 3500) * (t / sec) ** 2 * 0.25
    x = x * np.clip(gust, 0.5, 1.5)
    return fin(x, 0.15, 0.03)


def glider_open():  # 0.7 s cloth snap + flutter + soft whump
    sec = 0.7
    t = T(sec)
    snap = bp(white(sec), 700, 3500) * expd(sec, 16) * np.minimum(1, t / 0.002)
    flutter = bp(white(sec), 300, 2200) * expd(sec, 5) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t * np.exp(-t * 2))) * 0.4
    whump = np.sin(phase(np.linspace(110, 55, N(sec)))) * expd(sec, 9) * 0.9
    return fin(snap + flutter + whump, 0.001, 0.05)


def build_thunk():  # 0.4 s wood knock with a bright magic ping
    sec = 0.4
    knock = np.sin(phase(np.linspace(190, 105, N(sec)))) * expd(sec, 26) + bp(white(sec), 600, 2600) * expd(sec, 38) * 0.7
    ping = (np.sin(phase(np.full(N(sec), 1318.5))) + 0.5 * np.sin(phase(np.full(N(sec), 1975.5)))) * expd(sec, 9) * 0.22
    return fin(knock + ping, 0.001, 0.03)


def riser():  # 2.5 s tension riser (also used into the end card)
    sec = 2.5
    t = T(sec)
    amp = (t / sec) ** 2.6
    x = svf_bp(white(sec), 400 * (18 ** (t / sec)), 0.3) * amp + \
        np.sin(phase(220 * 2 ** (t / sec * 2))) * amp * 0.35 + hp(white(sec), 6000) * amp ** 1.5 * 0.2
    return fin(x, 0.02, 0.015)


def rocket_whoosh():  # 1.3 s launch thump + rocket sizzling towards the target
    sec = 1.3
    t = T(sec)
    thump = np.sin(phase(np.linspace(95, 50, N(sec)))) * expd(sec, 14) * 1.1
    fc = 700 + 3300 * (t / sec) ** 1.2
    flight = svf_bp(white(sec), fc, 0.6) * (0.15 + 0.85 * (t / sec) ** 1.5) + lp(white(sec), 500) * 0.4 * (t / sec)
    return fin(thump + flight, 0.002, 0.012)


def explosion():  # 3.2 s detonation, collapsing beams, rolling debris
    sec = 3.2
    t = T(sec)
    crack = hp(white(sec), 250) * expd(sec, 28) * 1.0
    body = lp(white(sec), 420) * expd(sec, 2.2) * 1.4 + boom(sec, 78, 28, 1.6, 9) * 1.4
    debris = np.zeros(N(sec))
    for _ in range(46):
        at = RNG.uniform(0.12, 2.4)
        i = N(at)
        k = np.arange(N(0.12))
        f = RNG.uniform(250, 1800)
        s = bp(white(0.12), f, f * 1.6) * np.exp(-k / SR * RNG.uniform(25, 60)) * RNG.uniform(0.15, 0.6) * np.exp(-at * 0.9)
        e = min(len(debris), i + len(s))
        debris[i:e] += s[:e - i]
    creak = bp(white(sec), 160, 520) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t)) * np.exp(-((t - 0.9) / 0.6) ** 2) * 0.25
    x = crack + body + debris * 0.9 + creak
    return reverb(x, wet=0.3, size=1.3, tail=0.5)[:N(sec)]


def boogie_burst():  # 1.4 s: bomb pops, shimmering arpeggio, wobbling bass
    sec = 1.4
    t = T(sec)
    pop = boom(sec, 180, 70, 8, 30) * 0.9 + hp(white(sec), 2500) * expd(sec, 30) * 0.5
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 2093.0]
    arp = np.zeros(N(sec))
    for k, f in enumerate(notes):
        at = 0.04 + k * 0.055
        i = N(at)
        s = np.sin(phase(np.full(N(0.7), f))) * expd(0.7, 5)
        e = min(len(arp), i + len(s))
        arp[i:e] += s[:e - i] * 0.25
    saw = 2 * ((np.cumsum(np.full(N(sec), 82.4)) / SR) % 1.0) - 1
    wub = lp(saw, 500) * (0.55 + 0.45 * np.sin(2 * np.pi * 8 * t)) * expd(sec, 2.6) * 0.7
    sparkle = hp(white(sec), 6000) * expd(sec, 4) * (RNG.uniform(size=N(sec)) > 0.93) * 1.4
    return reverb(fin(pop + arp + wub + sparkle, 0.001, 0.05), wet=0.25, tail=0.3)[:N(sec)]


def portal_hum():  # 3.0 s: swirling hum climbing in pitch, crackling more and more, then pulled away at the cut
    sec = 3.0
    t = T(sec)
    f = 100 * 2 ** (t / sec * 1.2)
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * (4 + 5 * t / sec) * t)
    hum = (np.sin(phase(f)) + 0.6 * np.sin(phase(f * 1.5)) + 0.3 * np.sin(phase(f * 2.01))) * trem
    density = 0.003 + 0.05 * (t / sec) ** 2
    imp = (RNG.uniform(size=N(sec)) < density) * RNG.uniform(-1, 1, N(sec))
    crackle = hp(lp(imp, 8000), 1500) * 2.0
    swirl = svf_bp(white(sec), 600 + 1800 * (0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t)), 0.4) * 0.4
    amp = np.minimum(1, t / 0.35) * (0.5 + 0.5 * (t / sec) ** 1.2)
    return tail_off((hum * 0.55 + crackle * 0.5 + swirl) * amp, 0.25)


def engine_rev():  # 3.8 s buggy: pull away, jump (in-air rev), crash landing at 3.2 s, rumble on
    sec = 3.8
    t = T(sec)
    rpm = np.interp(t, [0, 0.4, 1.9, 2.15, 2.9, 3.15, 3.2, 3.35, 3.8], [40, 48, 82, 95, 128, 135, 52, 58, 50])
    ph = phase(rpm)
    eng = (np.sin(ph) + 0.7 * np.sin(2 * ph) + 0.5 * np.sin(3 * ph + 0.5) + 0.35 * np.sin(5 * ph)) * (1 + 0.25 * np.sin(2 * np.pi * rpm * 0.5 * t / 1.0))
    eng = lp(np.sign(eng) * np.abs(eng) ** 0.8, 1400)
    grit = lp(white(sec), 900) * 0.25
    amp = np.interp(t, [0, 0.3, 2.0, 3.15, 3.2, 3.4, 3.8], [0.5, 0.8, 1.0, 1.0, 0.55, 0.6, 0.35])
    return tail_off((eng * 0.8 + grit) * amp, 0.15)


def landing_crash():  # 1.0 s metal and dirt
    sec = 1.0
    thump = np.sin(phase(np.linspace(120, 45, N(sec)))) * expd(sec, 12) * 1.3
    dirt = lp(white(sec), 1200) * expd(sec, 14) * 0.8
    metal = sum(np.sin(phase(np.full(N(sec), f * (1 + RNG.uniform(-0.01, 0.01))))) for f in (410, 640, 1010, 1730)) * expd(sec, 7) * 0.13
    spring = np.sin(phase(np.linspace(70, 40, N(sec)))) * np.exp(-((T(sec) - 0.22) / 0.07) ** 2) * 0.4
    return fin(thump + dirt + metal + spring, 0.001, 0.05)


def rain_bed():  # 5.4 s steady rain under the rainy shot, melting away before the end card
    sec = 5.4
    n = N(sec)
    f = np.fft.rfftfreq(n, 1 / SR)
    shape = np.where((f > 500) & (f < 9000), 1 / np.sqrt(np.maximum(f, 500) / 500), 0) * np.exp(-(f / 6500) ** 2)
    wash = np.fft.irfft(np.fft.rfft(RNG.standard_normal(n)) * shape, n)
    wash /= np.std(wash)
    body = lp(RNG.standard_normal(n), 400)
    body /= np.std(body)
    drops = np.zeros(n)
    for _ in range(300):
        i = int(RNG.integers(0, n - 400))
        k = np.arange(300)
        drops[i:i + 300] += np.sin(2 * np.pi * RNG.uniform(1500, 5500) * k / SR) * np.exp(-k / SR * 450) * RNG.uniform(0.15, 0.6)
    x = (wash * 0.9 + body * 0.3 + drops * 0.4)
    t = T(sec)
    return x * np.minimum(1, t / 0.4) * np.minimum(1, (sec - t) / 0.9)


def thunder_crack():  # 3.4 s lightning crack with a long rolling tail
    sec = 3.4
    t = T(sec)
    crack = hp(white(sec), 400) * expd(sec, 34) * 1.2 + lp(white(sec), 3000) * expd(sec, 16) * 0.5
    roll = lp(white(sec), 220)
    roll = roll / np.std(roll) * np.minimum(1, t / 0.12) * expd(sec, 1.2)
    for at, g in ((0.55, 0.45), (1.2, 0.3), (1.9, 0.2)):
        roll += lp(white(sec), 160) / 0.2 * g * np.exp(-((t - at) / 0.2) ** 2) * np.exp(-t / 2.2) * 0.3
    sub = boom(sec, 55, 28, 1.4, 6) * 0.9
    return tail_off(crack + roll * 0.6 + sub, 0.3)


def title_sting():  # 5.0 s: epic stab on the logo, electric crackle, choir-ish tail, fading out with the picture
    sec = 5.0
    t = T(sec)
    stab = np.zeros(N(sec))
    for f, g in ((55, 1.0), (82.4, 0.8), (110, 0.9), (165, 0.7), (220, 0.6), (329.6, 0.35)):
        stab += stack([f], sec, 0.006) * g
    stab = lp(stab, 1900) * (np.exp(-t * 1.4) * 0.7 + np.exp(-t * 0.45) * 0.3) * np.minimum(1, t / 0.012)
    choir = sum(np.sin(phase(np.full(N(sec), f * (1 + RNG.uniform(-0.004, 0.004))))) for f in (220, 329.6, 440, 659.3, 880)) / 5
    choir = choir * swell(sec, 0.3, 1.5, 1.1) * 0.5
    sub = boom(sec, 85, 30, 0.9, 10) * 1.6
    thumb = lp(white(sec), 2200) * expd(sec, 10) * 0.8 + hp(white(sec), 3500) * np.minimum(1, t / 0.1) * expd(sec, 1.4) * 0.3
    zap = np.zeros(N(sec))
    for at in np.sort(np.concatenate([RNG.uniform(0.05, 1.2, 8), RNG.uniform(1.2, 3.2, 6)])):
        i = N(at)
        k = np.arange(N(0.09))
        z = bp(white(0.09), RNG.uniform(1200, 3000), RNG.uniform(3500, 7000)) * np.exp(-k / SR * 40) * RNG.uniform(0.3, 0.8)
        e = min(len(zap), i + len(z))
        zap[i:e] += z[:e - i]
    x = reverb(stab * 1.1 + choir + sub + thumb + zap * 0.55, wet=0.4, size=1.5, tail=0.3)[:N(sec)]
    return tail_off(x, 1.4)


SOUNDS = {
    "trailer_opening_rise": opening_rise, "trailer_title_hit": title_hit, "trailer_whoosh_short": whoosh_short,
    "trailer_whoosh_big": whoosh_big, "trailer_hit": hit, "trailer_dive_wind": dive_wind,
    "trailer_glider_open": glider_open, "trailer_build_thunk": build_thunk, "trailer_riser": riser,
    "trailer_rocket_whoosh": rocket_whoosh, "trailer_explosion": explosion, "trailer_boogie_burst": boogie_burst,
    "trailer_portal_hum": portal_hum, "trailer_engine_rev": engine_rev, "trailer_landing_crash": landing_crash,
    "trailer_rain_bed": rain_bed, "trailer_thunder_crack": thunder_crack, "trailer_title_sting": title_sting,
}

# (time in the video [s], sound, gain, what happens on screen).  Whooshes start before the cut so their peak lands on it.
CUES = [
    (0.00, "trailer_opening_rise", 0.85, "fade in on the island aerial, dark swell then climbing riser to the first cut"),
    (1.00, "trailer_title_hit", 1.00, "STORM ISLAND title is fully visible"),
    (4.70, "trailer_whoosh_short", 0.80, "whoosh into cut 1 (aerial -> town fly-through)"),
    (5.00, "trailer_hit", 0.70, "cut 1: '50 FIGHTERS. ONE ISLAND.' fly-through begins"),
    (8.50, "trailer_whoosh_big", 0.90, "whoosh into cut 2 (fly-through -> sky dive)"),
    (9.00, "trailer_hit", 0.85, "cut 2: 'DROP IN. LOOT UP.' the dive begins"),
    (9.00, "trailer_dive_wind", 0.80, "free-fall wind rush builds"),
    (11.83, "trailer_glider_open", 0.95, "the glider opens"),
    (13.70, "trailer_whoosh_short", 0.80, "whoosh into the firefight"),
    (14.00, "trailer_hit", 0.95, "cut 3: 'FIGHT.' firefight begins"),
    (15.20, "trailer_whoosh_short", 0.55, "camera angle change"),
    (15.50, "trailer_hit", 0.60, "firefight angle 2"),
    (16.70, "trailer_whoosh_short", 0.55, "camera angle change"),
    (17.00, "trailer_hit", 0.65, "firefight angle 3"),
    (18.20, "trailer_whoosh_short", 0.55, "camera angle change"),
    (18.50, "trailer_hit", 0.70, "firefight angle 4"),
    (19.70, "trailer_whoosh_short", 0.65, "whoosh into the build shot"),
    (20.00, "trailer_hit", 0.80, "cut: 'BUILD.' begins"),
    (20.17, "trailer_build_thunk", 0.85, "first wall placed"),
    (20.63, "trailer_build_thunk", 0.85, "wall placed"),
    (21.10, "trailer_build_thunk", 0.90, "wall placed"),
    (21.57, "trailer_build_thunk", 0.90, "ramp placed"),
    (22.03, "trailer_build_thunk", 0.90, "wall placed"),
    (22.97, "trailer_build_thunk", 0.95, "last piece placed"),
    (22.50, "trailer_riser", 0.85, "riser into the next cut"),
    (24.70, "trailer_whoosh_big", 0.85, "whoosh into cut 'BREAK EVERYTHING.'"),
    (25.00, "trailer_hit", 0.90, "cut: 'BREAK EVERYTHING.' begins"),
    (27.20, "trailer_riser", 0.60, "tension riser into the rocket hit"),
    (28.55, "trailer_rocket_whoosh", 0.95, "rocket launched at the house"),
    (29.70, "trailer_explosion", 1.00, "the rocket hits: house explodes and collapses"),
    (30.70, "trailer_whoosh_short", 0.70, "whoosh into the llama cut"),
    (31.00, "trailer_hit", 0.80, "cut: 'LLAMAS. BOOGIE BOMBS. CHAOS.'"),
    (32.33, "trailer_boogie_burst", 0.95, "boogie bomb bursts, pink flash"),
    (33.00, "trailer_portal_hum", 0.85, "portal ring appears, hum swirls and crackles until the cut"),
    (35.70, "trailer_whoosh_short", 0.80, "whoosh into the driving shot"),
    (36.00, "trailer_hit", 0.85, "cut: 'DRIVE. EXPLORE.' buggy"),
    (36.20, "trailer_engine_rev", 0.60, "buggy engine: pull away, jump, in-air rev"),
    (38.05, "trailer_whoosh_short", 0.85, "buggy launches off the ramp"),
    (39.40, "trailer_landing_crash", 1.00, "buggy lands hard"),
    (39.70, "trailer_whoosh_big", 0.80, "whoosh into the rain shot"),
    (40.00, "trailer_hit", 0.95, "cut: 'SOLO - DUOS - TRIOS - SQUADS' in the rain"),
    (40.00, "trailer_rain_bed", 0.30, "rain begins"),
    (41.00, "trailer_thunder_crack", 1.00, "lightning flash"),
    (42.50, "trailer_riser", 0.90, "riser into the end card"),
    (44.45, "trailer_thunder_crack", 0.60, "second flash"),
    (45.00, "trailer_title_sting", 1.00, "cut: STORM ISLAND logo end card"),
]


def write(path, x, peak=0.92):
    x = A(x)
    m = np.max(np.abs(x))
    x = x / m * peak if m > 1e-9 else x
    wavfile.write(path, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def main():
    video = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VIDEO
    os.makedirs(AUDIO, exist_ok=True)
    os.makedirs(TRAILER, exist_ok=True)
    made = {}
    for name, fn in SOUNDS.items():
        x = fin(fn(), 0.001, 0.02)
        made[name] = A(x) / max(1e-9, np.max(np.abs(x)))
        write(os.path.join(AUDIO, name + ".wav"), made[name])
        print("  %-24s %5.2fs" % (name, len(x) / SR))

    fx = np.zeros(N(DUR))
    for at, name, gain, _ in CUES:
        x = made[name] * gain
        i = N(at)
        e = min(len(fx), i + len(x))
        fx[i:e] += x[:e - i]
    fx = np.tanh(fx * 0.9) / np.tanh(0.9)               # gentle glue so stacked hits do not clip
    fx = tail_off(fx, 0.05)
    write(os.path.join(AUDIO, "trailer_fx_mix.wav"), fx, 0.9)
    fx = fx / np.max(np.abs(fx)) * 0.9

    with open(os.path.join(TRAILER, "sync_cues.txt"), "w") as f:
        f.write("time_s  sound                     gain  event\n")
        for at, name, gain, why in sorted(CUES, key=lambda c: c[0]):
            f.write("%6.2f  %-24s %4.2f  %s\n" % (at, name, gain, why))

    # original music, ducked under the effects, then mux onto the untouched picture
    tmp = os.path.join(TRAILER, "_orig_audio.wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-vn", "-ac", "2", "-ar", "44100", tmp], check=True)
    sr, music = wavfile.read(tmp)
    os.remove(tmp)
    music = music.astype(float) / 32768.0
    n = int(DUR * sr)
    music = np.pad(music, ((0, max(0, n - len(music))), (0, 0)))[:n]
    fx44 = signal.resample_poly(fx, 2, 1)[:n]
    fx44 = np.pad(fx44, (0, n - len(fx44)))
    env = signal.lfilter(*signal.butter(2, 6 / (sr / 2)), np.abs(fx44))
    env = np.clip(env / np.percentile(env, 99), 0, 1)
    gain = 0.62 * (1 - 0.5 * env)
    mix = music * gain[:, None] + fx44[:, None] * 0.95
    mix = np.tanh(mix * 0.95) / np.tanh(0.95)
    mix = mix / np.max(np.abs(mix)) * 0.93
    mixwav = os.path.join(TRAILER, "_mix.wav")
    wavfile.write(mixwav, sr, (mix * 32767).astype(np.int16))
    out = os.path.join(TRAILER, "StormIsland-trailer-epic.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-i", mixwav, "-map", "0:v:0", "-map", "1:a:0",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out], check=True)
    os.remove(mixwav)
    print("wrote", out)


if __name__ == "__main__":
    main()
