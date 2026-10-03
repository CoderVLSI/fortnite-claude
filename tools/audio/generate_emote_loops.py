#!/usr/bin/env python3
"""Synthesise the eight emote dance loops (and the emote-wheel UI sound) for Storm Island.

    python3 tools/audio/generate_emote_loops.py             # write everything to assets/audio/
    python3 tools/audio/generate_emote_loops.py emote_robot_loop      # just one
    python3 tools/audio/generate_emote_loops.py --verify              # measure the files on disk
    python3 tools/audio/generate_emote_loops.py --list

Needs numpy (same as generate_audio.py) and ffmpeg (loudness measurement only). Everything is original:
the notes below are written by hand per emote, rendered with simple chiptune / synth voices, no samples.

How the loops are made seamless
  * Every voice is mixed into a circular buffer of exactly `bars` bars, so note tails that run past the
    end wrap round into the start instead of being cut off.
  * Filters run over three copies of the loop and keep the middle one, so they have no start-up transient.
  * Gain and limiter are memoryless, and a 3 ms raised-cosine fade puts the first and last sample at zero.
  --verify checks all of it numerically (seam smoothness, start/end energy, loudness, peak, sub-80 Hz).

Mastering: 24 dB/oct high-pass at 70 Hz (tidy low end), soft limiter at -1 dBFS, then gain iterated until the
file measures -14 LUFS (EBU R128 integrated, as measured by ffmpeg).
Output: mono, 22050 Hz, 16-bit PCM WAV.
"""
import math
import os
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 22050
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
TARGET_LUFS = -14.0
CEIL = 10 ** (-1.0 / 20)        # -1 dBFS
HPF_HZ = 70.0
FADE_S = 0.003
RNG = np.random.default_rng(0)


# ------------------------------------------------------------------ notes, filters, oscillators

def midi(name):
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    n = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[m[1]] + {"#": 1, "b": -1, "": 0}[m[2]]
    return 12 * (int(m[3]) + 1) + n


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def bq_coeffs(kind, fc, q=0.7071):
    assert 10 < fc < 0.45 * SR, "filter frequency %g Hz is outside the stable range for %d Hz audio" % (fc, SR)
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
    return [v / a0 for v in b], [-2 * c / a0, (1 - al) / a0]


def bq(x, kind, fc, q=0.7071):
    b, a = bq_coeffs(kind, fc, q)
    y = np.empty(len(x))
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    a1, a2 = a
    for i, v in enumerate(x.tolist()):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, o
        y[i] = o
    return y


def periodic(x, fn):
    """Run a filter so it is seamless around the loop point: filter 3 copies, keep the middle."""
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def blep(ph, dt):
    out = np.zeros_like(ph)
    m = ph < dt
    x = ph[m] / dt
    out[m] = x + x - x * x - 1
    m = ph > 1 - dt
    x = (ph[m] - 1) / dt
    out[m] = x * x + x + x + 1
    return out


def saw(f, n, phase=0.0):
    dt = f / SR
    ph = (phase + dt * np.arange(n)) % 1.0
    return 2 * ph - 1 - blep(ph, dt)


def pulse(f, n, w=0.5):
    dt = f / SR
    ph = (dt * np.arange(n)) % 1.0
    ph2 = (ph + w) % 1.0
    return ((2 * ph - 1 - blep(ph, dt)) - (2 * ph2 - 1 - blep(ph2, dt))) * 0.5


def tri(f, n):
    ph = (f / SR * np.arange(n)) % 1.0
    return 2 * np.abs(2 * ph - 1) - 1


def adsr(gate, a=0.003, d=0.08, s=0.6, r=0.03):
    gate = max(int(gate), 4)
    rs = max(int(r * SR), 2)
    n = gate + rs
    t = np.arange(n)
    e = np.minimum(t / max(a * SR, 1), 1.0) * (s + (1 - s) * np.exp(-np.maximum(t - a * SR, 0) / max(d * SR / 3, 1)))
    e[gate:] = e[gate - 1] * np.linspace(1, 0, rs)
    return e


# ------------------------------------------------------------------ instruments  (midi note, gate samples) -> samples

def i_square(m, gate, w=0.5):
    e = adsr(gate, 0.002, 0.06, 0.6, 0.02)
    return pulse(hz(m), len(e), w) * e


def i_pulse25(m, gate):
    return i_square(m, gate, 0.25)


def i_saw(m, gate):
    e = adsr(gate, 0.004, 0.12, 0.55, 0.04)
    f = hz(m)
    return 0.5 * (saw(f, len(e)) + saw(f * 1.006, len(e), 0.37)) * e


def i_brass(m, gate):
    e = adsr(gate, 0.02, 0.15, 0.7, 0.06)
    f = hz(m)
    return 0.5 * (saw(f, len(e)) + saw(f * 0.994, len(e), 0.21)) * e


def i_pad(m, gate):
    e = adsr(gate, 0.06, 0.2, 0.85, 0.25)
    f = hz(m)
    return (saw(f, len(e)) + saw(f * 1.01, len(e), 0.3) + saw(f * 0.99, len(e), 0.6)) / 3.0 * e


def i_tri(m, gate):
    e = adsr(gate, 0.004, 0.1, 0.85, 0.05)
    return tri(hz(m), len(e)) * e


def i_sine(m, gate):
    e = adsr(gate, 0.006, 0.12, 0.8, 0.07)
    return np.sin(2 * math.pi * hz(m) * np.arange(len(e)) / SR) * e


def i_pluck(m, gate):
    e = adsr(gate, 0.002, 0.07, 0.08, 0.03)
    return i_saw_raw(m, len(e)) * e


def i_saw_raw(m, n):
    return saw(hz(m), n)


def _bell(m, gate, ring, brightness=1.0):
    n = gate + int(ring * SR)
    t = np.arange(n) / SR
    f = hz(m)
    y = np.zeros(n)
    for ratio, amp, dec in [(1.0, 1.0, ring * 0.5), (2.0, 0.45, ring * 0.35), (2.76, 0.30 * brightness, ring * 0.22),
                            (5.4, 0.14 * brightness, ring * 0.12)]:
        y += amp * np.sin(2 * math.pi * f * ratio * t) * np.exp(-t / dec)
    y *= np.minimum(np.arange(n) / (0.002 * SR), 1.0)
    return y / 1.6


def i_bell(m, gate):
    return _bell(m, gate, 0.55)


def i_bellsoft(m, gate):
    return _bell(m, gate, 0.7, 0.25)


def i_epiano(m, gate):
    n = gate + int(0.25 * SR)
    t = np.arange(n) / SR
    f = hz(m)
    mod = 1.6 * np.exp(-t / 0.10) * np.sin(2 * math.pi * f * t)
    y = np.sin(2 * math.pi * f * t + mod) * np.exp(-t / 0.55)
    y += 0.12 * np.sin(2 * math.pi * f * 4 * t) * np.exp(-t / 0.05)       # tine
    y *= np.minimum(np.arange(n) / (0.004 * SR), 1.0)
    y[gate:] *= np.linspace(1, 0, n - gate)
    return y * 0.8


def i_808(m, gate):
    n = gate + int(0.12 * SR)
    t = np.arange(n) / SR
    f = hz(m)
    ph = 2 * math.pi * np.cumsum(f * (1 + 0.6 * np.exp(-t / 0.025))) / SR
    y = np.sin(ph) * np.exp(-t / 0.55) * np.minimum(np.arange(n) / (0.002 * SR), 1.0)
    y = np.tanh(2.4 * y) * 0.62
    y[gate:] *= np.linspace(1, 0, n - gate)
    return y


INST = {"square": i_square, "pulse25": i_pulse25, "saw": i_saw, "brass": i_brass, "pad": i_pad, "tri": i_tri,
        "sine": i_sine, "pluck": i_pluck, "bell": i_bell, "bellsoft": i_bellsoft, "epiano": i_epiano, "808": i_808}


# ------------------------------------------------------------------ drums

def _fade_tail(y, ms=5):
    k = min(int(ms / 1000 * SR), len(y))
    y[-k:] *= np.linspace(1, 0, k)
    return y


def d_kick(f0=50, f1=150, dec=0.10, dur=0.3, click=0.25, drive=1.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * math.pi * np.cumsum(f0 + (f1 - f0) * np.exp(-t / 0.02)) / SR
    att = np.minimum(t / 0.001, 1.0)
    y = np.sin(ph) * np.exp(-t / dec) * att
    y += click * RNG.standard_normal(n) * np.exp(-t / 0.003) * att
    return _fade_tail(np.tanh(drive * y) * 0.9)


def d_snare(tone=190, dec=0.08, dur=0.22, lo=900, hi=7000, tone_gain=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = bq(bq(RNG.standard_normal(n), "hp", lo), "lp", hi)
    y = nz * np.exp(-t / dec) + tone_gain * np.sin(2 * math.pi * tone * t) * np.exp(-t / 0.05)
    y *= np.minimum(t / 0.0007, 1.0)
    return _fade_tail(y * 0.7)


def d_clap(dur=0.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = bq(bq(RNG.standard_normal(n), "hp", 900), "lp", 5500)
    env = np.zeros(n)
    for off in (0.0, 0.009, 0.018):
        k = int(off * SR)
        env[k:] += np.exp(-np.arange(n - k) / SR / 0.012) * 0.6
    env += np.exp(-t / 0.07) * 0.5 * (t >= 0.018)
    env *= np.minimum(t / 0.0007, 1.0)
    return _fade_tail(nz * env * 0.8)


def d_snare8(dur=0.16, hold=3, dec=0.05):
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = np.repeat(RNG.uniform(-1, 1, n // hold + 1), hold)[:n]
    v = np.sign(v) * (np.abs(v) > 0.15)
    return _fade_tail(v * np.exp(-t / dec) * np.minimum(t / 0.0005, 1.0) * 0.6)


def d_hat(dec=0.02, dur=0.12, hp=6500, hold=1):
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = RNG.standard_normal(n // hold + 1)
    nz = np.repeat(base, hold)[:n] if hold > 1 else base[:n]
    nz = bq(nz, "hp", hp)
    return _fade_tail(nz * np.exp(-t / dec) * np.minimum(t / 0.0005, 1.0) * 0.5)


def d_rim(dur=0.06):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * math.pi * 1700 * t) * np.exp(-t / 0.008) + 0.4 * bq(RNG.standard_normal(n), "bp", 3000, 2) * np.exp(-t / 0.01)
    return _fade_tail(y * np.minimum(t / 0.0005, 1.0) * 0.6)


# ------------------------------------------------------------------ sequencing

class Seq:
    def __init__(self, bpm, bars, swing=0.0):
        self.step = 60.0 / bpm / 4 * SR          # samples per 16th
        self.bars = bars
        self.n = int(round(bars * 16 * self.step))
        self.swing = swing

    def pos(self, bar, step):
        base = (bar * 16 + step) * self.step
        if int(step) % 4 in (2, 3) and abs(step - round(step)) < 1e-9:
            base += self.swing * 2 * self.step   # shuffle the off-beat eighths
        return base


class Loop:
    def __init__(self, n):
        self.n = n
        self.b = np.zeros(n)

    def add(self, start, sig, gain=1.0):
        i = int(round(start)) % self.n
        sig = sig * gain
        while len(sig):
            k = min(len(sig), self.n - i)
            self.b[i:i + k] += sig[:k]
            sig = sig[k:]
            i = 0


TOKEN = re.compile(r"(\d+(?:\.\d+)?):([^/\s]+)(?:/(\d+(?:\.\d+)?))?")


def parse(s):
    return [(float(m[1]), m[2], float(m[3] or 1)) for m in TOKEN.finditer(s)]


def pick(v, i):
    return v[i % len(v)] if isinstance(v, (list, tuple)) else v


def alt(tops, pedal):
    """Robot 'beep boop': alternate a melody note and a pedal note on 16ths."""
    return " ".join("%d:%s/0.5 %d:%s/0.5" % (2 * i, t, 2 * i + 1, pedal) for i, t in enumerate(tops))


def build(spec):
    global RNG
    RNG = np.random.default_rng(spec["seed"])
    sq = Seq(spec["bpm"], spec["bars"], spec.get("swing", 0.0))
    stems = {k: Loop(sq.n) for k in ("drums", "bass", "lead", "comp", "arp", "extra")}
    mix = spec["mix"]
    chords = [[midi(n) for n in c] for c in spec["chords"]]
    roots = [midi(r) for r in spec["roots"]]

    # drums
    kit = spec["kit"]
    sounds = {name: fn(**kw) for name, (fn, kw, _g) in kit.items()}
    for bar in range(sq.bars):
        for name, (_fn, _kw, g) in kit.items():
            pat = spec["fills"].get(bar, {}).get(name) if spec.get("fills") else None
            pat = pat or pick(spec["drums"].get(name, "." * 16), bar)
            for s, ch in enumerate(pat):
                if ch != ".":
                    vel = {"x": 1.0, "o": 0.5, "X": 1.3}[ch]
                    stems["drums"].add(sq.pos(bar, s), sounds[name], g * vel)

    def play_notes(stem, strings, inst, gain, use_chord=False, strum=0.0, legato=0.92):
        for bar in range(sq.bars):
            for step, tok, ln in parse(pick(strings, bar)):
                gate = max(int(ln * sq.step * legato), 8)
                if tok == "*":
                    for k, m in enumerate(pick(chords, bar)):
                        stems[stem].add(sq.pos(bar, step) + k * strum * SR, INST[inst](m, gate), gain)
                    continue
                if tok.startswith("r"):
                    m = pick(roots, bar) + int(tok[1:] or 0)
                else:
                    m = midi(tok)
                stems[stem].add(sq.pos(bar, step), INST[inst](m, gate), gain)

    if "bass" in spec:
        play_notes("bass", spec["bass"]["notes"], spec["bass"]["inst"], spec["bass"]["gain"])
    if "lead" in spec:
        play_notes("lead", spec["lead"]["notes"], spec["lead"]["inst"], spec["lead"]["gain"])
    if "comp" in spec:
        c = spec["comp"]
        play_notes("comp", c["notes"], c["inst"], c["gain"], strum=c.get("strum", 0.0))
    if "arp" in spec:
        a = spec["arp"]
        every = a.get("every", 1)
        for bar in range(sq.bars):
            ch = pick(chords, bar)
            for s in range(0, 16, every):
                idx = a["idx"][(s // every) % len(a["idx"])]
                acc = 1.0 if s % 4 == 0 else 0.7
                gate = int(a.get("len", 1.0) * every * sq.step)
                stems["arp"].add(sq.pos(bar, s), INST[a["inst"]](ch[idx], gate), a["gain"] * acc)
    if spec.get("crackle"):
        n = sq.n
        hiss = bq(RNG.standard_normal(n), "hp", 2500) * 0.004
        clicks = np.zeros(n)
        for p in RNG.integers(0, n, int(n / SR * 7)):
            clicks[p] = RNG.uniform(-1, 1) * RNG.choice([0.05, 0.12, 0.25])
        stems["extra"].b += hiss + bq(clicks, "lp", 5000)

    out = np.zeros(sq.n)
    for k, st in stems.items():
        out += st.b * mix.get(k, 1.0)
    return out, sq


# ------------------------------------------------------------------ mastering

def limit(y, c=CEIL, knee=0.6):
    a = np.abs(y)
    k = knee * c
    out = y.copy()
    o = a > k
    out[o] = np.sign(y[o]) * (k + (c - k) * np.tanh((a[o] - k) / (c - k)))
    return out


def fade_edges(y):
    m = int(FADE_S * SR)
    w = (1 - np.cos(np.pi * np.arange(m) / m)) / 2
    y = y.copy()
    y[:m] *= w
    y[-m:] *= w[::-1]
    return y


def write_wav(path, y):
    pcm = np.round(np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, SR), "unexpected format: " + path
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


def lufs_file(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", err)[-1])


def master(mix, path, lpf=None):
    x = periodic(mix, lambda z: bq(bq(z, "hp", HPF_HZ), "hp", HPF_HZ))
    if lpf:
        x = periodic(x, lambda z: bq(z, "lp", lpf))
    g = 0.3 / np.max(np.abs(x))
    for _ in range(10):
        y = fade_edges(limit(x * g))
        write_wav(path, y)
        err = TARGET_LUFS - lufs_file(path)
        if abs(err) < 0.08:
            break
        g *= 10 ** (err / 20)
    return y


# ------------------------------------------------------------------ the eight emotes

KITS = {
    "disco": {"kick": (d_kick, dict(f0=52, f1=160, dec=0.10), 0.9), "snare": (d_clap, {}, 0.75),
              "hat": (d_hat, dict(dec=0.018), 0.45), "ohat": (d_hat, dict(dec=0.11, dur=0.2), 0.45)},
    "electro": {"kick": (d_kick, dict(f0=50, f1=180, dec=0.09, drive=1.7), 0.95),
                "snare": (d_snare, dict(tone=210, dec=0.07, tone_gain=0.6), 0.85), "clap": (d_clap, {}, 0.55),
                "hat": (d_hat, dict(dec=0.016), 0.4), "ohat": (d_hat, dict(dec=0.10, dur=0.2), 0.4)},
    "chip": {"kick": (d_kick, dict(f0=60, f1=200, dec=0.06, drive=2.0, click=0.1), 0.9),
             "snare": (d_snare8, {}, 0.7), "hat": (d_hat, dict(dec=0.012, hold=2, hp=4000), 0.4)},
    "chipfan": {"kick": (d_kick, dict(f0=58, f1=190, dec=0.07, drive=1.8), 0.95), "snare": (d_snare8, dict(dec=0.07), 0.8),
                "hat": (d_hat, dict(dec=0.014, hold=2, hp=4500), 0.4)},
    "sparkle": {"kick": (d_kick, dict(f0=52, f1=150, dec=0.08, drive=1.2), 0.7), "clap": (d_clap, {}, 0.45),
                "hat": (d_hat, dict(dec=0.014), 0.3)},
    "trap": {"kick": (d_kick, dict(f0=48, f1=140, dec=0.12, drive=1.5), 0.85), "snare": (d_clap, {}, 0.9),
             "hat": (d_hat, dict(dec=0.012), 0.42), "ohat": (d_hat, dict(dec=0.09, dur=0.18), 0.4)},
    "soft": {"kick": (d_kick, dict(f0=52, f1=120, dec=0.09, drive=1.0, click=0.1), 0.6), "rim": (d_rim, {}, 0.5),
             "hat": (d_hat, dict(dec=0.02, hp=7000), 0.28)},
    "lofi": {"kick": (d_kick, dict(f0=54, f1=110, dec=0.11, drive=1.0, click=0.05), 0.75),
             "snare": (d_snare, dict(tone=180, dec=0.09, lo=500, hi=3500, tone_gain=0.4), 0.6),
             "hat": (d_hat, dict(dec=0.025, hp=5000), 0.3)},
}

TRACKS = {
    # --- Boogie Down: funky disco, 118 BPM, A dorian-ish, square bass + bouncy lead
    "emote_boogie_loop": dict(
        bpm=118, bars=4, seed=11, kit=KITS["disco"], lpf=9000,
        roots=["A2", "D3", "A2", "E3"],
        chords=[["C4", "E4", "G4", "A4"], ["C4", "F#4", "A4", "D5"], ["C4", "E4", "G4", "A4"], ["D4", "G#4", "B4", "E5"]],
        drums=dict(kick="x...x...x...x...", snare="....x.......x...", hat=".o.o.o.o.o.o.o.o", ohat="..x...x...x...x."),
        fills={},
        bass=dict(inst="square", gain=0.55, notes=[
            "0:r 2:r+12 3:r 4:r 6:r+12 7:r-2 8:r 10:r+12 11:r 12:r 14:r+3 15:r+7",
            "0:r 2:r+12 3:r 4:r 6:r+12 7:r-2 8:r 10:r+12 11:r 12:r 14:r+4 15:r+9",
            "0:r 2:r+12 3:r 4:r 6:r+12 7:r-2 8:r 10:r+12 11:r 12:r 14:r+3 15:r+7",
            "0:r 2:r+12 3:r 4:r 6:r+12 7:r-2 8:r 10:r+12 11:r 12:r+4 14:r+7 15:r+10"]),
        lead=dict(inst="square", gain=0.34, notes=[
            "0:E5 2:E5 3:G5 4:A5/2 8:G5 10:E5 11:D5 12:E5/3",
            "0:D5 2:D5 3:E5 4:G5/2 8:E5 10:D5 11:C5 12:D5/3",
            "0:E5 2:E5 3:G5 4:A5/2 8:C6 10:A5 11:G5 12:E5/3",
            "0:D5 2:E5 3:B4 4:D5/2 8:E5/2 12:D5 13:B4 14:A4/2"]),
        comp=dict(inst="pulse25", gain=0.20, notes=["3:*/1 6:*/1 11:*/1 14:*/1"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, comp=1.0)),

    # --- Hip Swing: punchy electro/pop, 128 BPM, C minor, saw bass + snappy snare
    "emote_floss_loop": dict(
        bpm=128, bars=8, seed=12, kit=KITS["electro"], lpf=9000,
        roots=["C3", "Ab2", "Eb3", "Bb2"],
        chords=[["G4", "C5", "Eb5"], ["Ab4", "C5", "Eb5"], ["G4", "Bb4", "Eb5"], ["F4", "Bb4", "D5"]],
        drums=dict(kick="x...x...x...x...", snare="....x.......x.o.", clap="....x.......x...", hat="o.x.o.x.o.x.o.x.", ohat="........"),
        fills={7: dict(snare="....x.......xooo", kick="x...x...x.......")},
        bass=dict(inst="saw", gain=0.5, notes=["0:r 2:r 3:r+12 4:r 6:r 7:r+12 8:r 10:r 11:r+12 12:r 14:r 15:r+12"]),
        lead=dict(inst="saw", gain=0.30, notes=[
            "0:G5/2 3:G5 4:Eb5/2 8:F5/2 11:G5 12:Bb5/3",
            "0:Ab5/2 3:Ab5 4:G5/2 8:Eb5/2 11:F5 12:G5/3",
            "0:Bb5/2 3:Bb5 4:G5/2 8:Eb5/2 11:G5 12:Bb5/3",
            "0:D6/2 3:D6 4:Bb5/2 8:F5/2 11:Bb5 12:D6/3",
            "0:G5/2 3:G5 4:Eb5/2 8:F5/2 11:G5 12:Bb5/3",
            "0:Ab5/2 3:Ab5 4:G5/2 8:Eb5/2 11:F5 12:G5/3",
            "0:Bb5/2 3:Bb5 4:G5/2 8:Eb5/2 11:G5 12:Bb5/3",
            "0:F6/2 3:D6 4:Bb5/2 8:C6 10:D6 12:F6/4"]),
        comp=dict(inst="saw", gain=0.16, notes=["2:*/1 6:*/1 10:*/1 14:*/1"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, comp=1.0)),

    # --- Beep Boop: stiff 8-bit robot, 112 BPM, A minor, pulse leads + mechanical hats
    "emote_robot_loop": dict(
        bpm=112, bars=4, seed=13, kit=KITS["chip"], lpf=9000,
        roots=["A2", "F2", "C3", "G2"],
        chords=[["A4", "C5", "E5"], ["F4", "A4", "C5"], ["E4", "G4", "C5"], ["D4", "G4", "B4"]],
        drums=dict(kick="x.......x.......", snare="....x.......x...", hat="x.x.x.x.x.x.x.x."),
        fills={},
        bass=dict(inst="square", gain=0.5, notes=["0:r/1 2:r/1 4:r/1 6:r/1 8:r/1 10:r/1 12:r/1 14:r/1"]),
        lead=dict(inst="pulse25", gain=0.34, notes=[
            alt(["A5", "C6", "B5", "A5", "E6", "C6", "B5", "A5"], "E5"),
            alt(["F5", "A5", "G5", "F5", "C6", "A5", "G5", "F5"], "C5"),
            alt(["E5", "G5", "F5", "E5", "C6", "G5", "F5", "E5"], "C5"),
            alt(["D6", "B5", "A5", "G5", "B5", "D6", "C6", "B5"], "D5")]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0)),

    # --- Twirl: fast sparkly arpeggios, 138 BPM, D major, bells + triangle bass
    "emote_twirl_loop": dict(
        bpm=138, bars=8, seed=14, kit=KITS["sparkle"], lpf=9000,
        roots=["D3", "A2", "B2", "G2", "D3", "A2", "B2", "A2"],
        chords=[["D5", "F#5", "A5", "D6"], ["A4", "C#5", "E5", "A5"], ["B4", "D5", "F#5", "B5"], ["G4", "B4", "D5", "G5"],
                ["D5", "F#5", "A5", "D6"], ["A4", "C#5", "E5", "A5"], ["B4", "D5", "F#5", "B5"], ["A4", "C#5", "E5", "A5"]],
        drums=dict(kick="x...x...x...x...", clap="....x.......x...", hat="o.o.o.o.o.o.o.o."), fills={},
        bass=dict(inst="tri", gain=0.5, notes=["0:r/3 4:r/3 8:r/3 12:r/3"]),
        arp=dict(inst="bell", gain=0.28, idx=[0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 1], len=1.1),
        lead=dict(inst="bell", gain=0.34, notes=[
            "0:F#6/3 4:A6/3 8:D7/4", "0:E6/3 4:C#7/3 8:A6/4", "0:D7/3 4:B6/3 8:F#6/4", "0:G6/3 4:B6/3 8:D7/2 12:B6/2",
            "0:F#6/3 4:A6/3 8:D7/4", "0:E6/3 4:A6/3 8:C#7/4", "0:D7/2 2:C#7/2 4:B6/4 8:F#6/4",
            "0:E6/2 2:A6/2 4:C#7/2 6:E7/2 8:A6/4"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, arp=1.0)),

    # --- Victory Hop: triumphant chiptune fanfare, 144 BPM, C major, driving
    "emote_cheer_loop": dict(
        bpm=144, bars=8, seed=15, kit=KITS["chipfan"], lpf=9000,
        roots=["C3", "G2", "A2", "F2", "C3", "G2", "F2", "G2"],
        chords=[["E4", "G4", "C5"], ["D4", "G4", "B4"], ["E4", "A4", "C5"], ["F4", "A4", "C5"],
                ["E4", "G4", "C5"], ["D4", "G4", "B4"], ["F4", "A4", "C5"], ["D4", "G4", "B4"]],
        drums=dict(kick="x...x...x...x...", snare="....x.......x...", hat="x.x.x.x.x.x.x.x."),
        fills={7: dict(snare="....x...x.x.xxxx", kick="x...x...x...x...")},
        bass=dict(inst="square", gain=0.5, notes=["0:r/2 2:r+12/2 4:r/2 6:r+12/2 8:r/2 10:r+12/2 12:r/2 14:r+12/2"]),
        lead=dict(inst="square", gain=0.34, notes=[
            "0:C5/2 2:E5 3:G5 4:C6/4 8:G5/2 10:E5/2 12:G5/4",
            "0:B5/2 2:D6 3:B5 4:G5/4 8:D5/2 10:G5/2 12:B5/4",
            "0:A5/2 2:C6 3:E6 4:A5/4 8:E5/2 10:A5/2 12:C6/4",
            "0:A5/2 2:C6 3:F6 4:C6/4 8:A5/2 10:F5/2 12:A5/4",
            "0:E6/2 2:G6 3:E6 4:C6/2 6:E6/2 8:G6/6 14:E6/2",
            "0:D6/2 2:G6 3:D6 4:B5/2 6:D6/2 8:G6/6 14:D6/2",
            "0:C6/2 2:F6 3:C6 4:A5/2 6:C6/2 8:F6/6 14:C6/2",
            "0:D6/2 2:G6/2 4:B5/2 6:D6/2 8:G6/2 10:B6/2 12:D6/2 14:G6/2"]),
        comp=dict(inst="pulse25", gain=0.16, notes=["0:*/6 8:*/6"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, comp=1.0)),

    # --- Power Pose: heavy slow trap strut, 92 BPM, F minor, 808 bass
    "emote_flex_loop": dict(
        bpm=92, bars=4, seed=16, kit=KITS["trap"], lpf=9000,
        roots=["F2", "Db3", "Ab2", "Eb3"],
        chords=[["C4", "F4", "Ab4"], ["Db4", "F4", "Ab4"], ["C4", "Eb4", "Ab4"], ["Bb3", "Eb4", "G4"]],
        drums=dict(kick="x......x..x.....", snare="........x.......",
                   hat=["x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.xxx.", "x.x.x.x.x.x.x.x.", "x.x.x.x.xxx.x.xx"], ohat="..............x."),
        fills={},
        bass=dict(inst="808", gain=0.62, notes=["0:r/5 6:r/1 8:r/3 11:r/1 14:r/2"]),
        lead=dict(inst="brass", gain=0.30, notes=[
            "0:C5/3 4:Ab4/2 6:C5/2 8:F5/6", "0:Db5/3 4:C5/2 6:Ab4/2 8:F4/6",
            "0:Eb5/3 4:C5/2 6:Eb5/2 8:Ab5/6", "0:Bb4/3 4:G4/2 6:Bb4/2 8:Eb5/4 12:C5/2 14:Bb4/2"]),
        comp=dict(inst="pad", gain=0.14, notes=["0:*/15"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, comp=1.0)),

    # --- Hello There: gentle friendly melody, 100 BPM, G major, soft bells
    "emote_wave_loop": dict(
        bpm=100, bars=4, seed=17, kit=KITS["soft"], lpf=8000,
        roots=["G2", "E3", "C3", "D3"],
        chords=[["G4", "B4", "D5", "G5"], ["E4", "G4", "B4", "E5"], ["E4", "G4", "C5", "E5"], ["D4", "F#4", "A4", "D5"]],
        drums=dict(kick="x.......x.......", rim="............o...", hat="..o...o...o...o."),
        fills={3: dict(kick="x.......x.....o.", rim="............o.o.", hat="..o...o...o.o.o.")},
        bass=dict(inst="tri", gain=0.5, notes=["0:r/6 8:r/6", "0:r/6 8:r/6", "0:r/6 8:r/6", "0:r/6 8:r/4 12:r+7/2 14:r+10/2"]),
        arp=dict(inst="pluck", gain=0.10, every=2, idx=[0, 1, 2, 1, 3, 2, 1, 2], len=1.0),
        lead=dict(inst="bellsoft", gain=0.42, notes=[
            "0:B4/2 2:D5/2 4:G5/4 8:E5/2 10:D5/2 12:B4/4", "0:E5/2 2:G5/2 4:B5/4 8:G5/2 10:E5/2 12:D5/4",
            "0:C5/2 2:E5/2 4:G5/4 8:E5/2 10:C5/2 12:E5/4", "0:D5/2 2:F#5/2 4:A5/4 8:F#5/2 10:D5/2 12:A4/2 14:B4/2"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, arp=1.0)),

    # --- Take a Seat: lazy lo-fi chill, 76 BPM, C major jazz chords, swing
    "emote_sit_loop": dict(
        bpm=76, bars=4, seed=18, swing=0.28, kit=KITS["lofi"], lpf=4800, crackle=True,
        roots=["C3", "A2", "D3", "G2"],
        chords=[["E3", "G3", "B3", "C4"], ["E3", "G3", "C4", "E4"], ["F3", "A3", "C4", "D4"], ["F3", "G3", "B3", "D4"]],
        drums=dict(kick="x.....x..x......", snare="....x.......x...", hat="x.x.x.x.x.x.x.x."),
        fills={3: dict(kick="x.....x..x....o.", snare="....x.......x.o.", hat="x.x.x.x.x.xxx.xx")},
        bass=dict(inst="sine", gain=0.6, notes=["0:r/4 6:r/1 8:r+7/3 12:r/2", "0:r/4 6:r/1 8:r+7/3 12:r/2", "0:r/4 6:r/1 8:r+7/3 12:r/2",
                                                "0:r/4 6:r/1 8:r+7/3 12:r+7/1 14:r+10/2"]),
        comp=dict(inst="epiano", gain=0.24, strum=0.012, notes=["0:*/6 6:*/2 10:*/2", "0:*/6 6:*/2 10:*/2", "0:*/6 6:*/2 10:*/2",
                                                              "0:*/6 6:*/2 10:*/2 14:*/2"]),
        lead=dict(inst="epiano", gain=0.30, notes=[
            "0:E5/3 4:G5/2 6:B5/2 8:A5/4 12:G5/2", "0:E5/3 4:C5/2 6:E5/2 8:G5/4 12:E5/2",
            "0:F5/3 4:A5/2 6:C6/2 8:A5/4 12:F5/2", "0:D5/3 4:F5/2 6:D5/2 8:B4/4 12:D5/2 14:B4/2"]),
        mix=dict(drums=1.0, bass=1.0, lead=1.0, comp=1.0, extra=1.0)),
}


def wheel_open():
    """emote_wheel_open: 0.15 s soft whoosh + tick, UI sound (peak -4 dBFS, not loudness-normalised)."""
    n = int(0.15 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(99)
    nz = bq(rng.standard_normal(n), "bp", 1400, 0.9)
    env = np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.045)
    sweep = np.sin(2 * math.pi * np.cumsum(500 + 1700 * (t / 0.15) ** 1.5) / SR) * env * 0.25
    tick = np.sin(2 * math.pi * 1800 * t) * np.exp(-t / 0.006) * np.minimum(t / 0.0008, 1.0) * 0.35
    y = nz * env * 1.4 + sweep + tick
    y[-int(0.012 * SR):] *= np.linspace(1, 0, int(0.012 * SR))
    return y / np.max(np.abs(y)) * 10 ** (-4 / 20)


# ------------------------------------------------------------------ verification

def verify(name):
    spec = TRACKS[name]
    path = os.path.join(OUT, name + ".wav")
    y = read_wav(path)
    n = len(y)
    beat = int(60.0 / spec["bpm"] * SR)
    expect = int(round(spec["bars"] * 4 * 60.0 / spec["bpm"] * SR))
    dur = n / SR
    peak = 20 * math.log10(np.max(np.abs(y)))
    lufs = lufs_file(path)
    rms = lambda a: math.sqrt(float(np.mean(a * a)) + 1e-18)
    e_diff = 20 * math.log10(rms(y[:beat]) / rms(y[-beat:]))
    # seam smoothness: play the loop end into its start and compare the curvature there with the loop's own
    z = np.concatenate([y[-64:], y[:64]])
    seam_d2 = float(np.max(np.abs(np.diff(z, 2))))
    d2 = np.abs(np.diff(y, 2))
    d2_ref = float(np.percentile(d2, 99.9))
    spec_f = np.abs(np.fft.rfft(y)) ** 2
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    sub = float(spec_f[freqs < 80].sum() / spec_f.sum() * 100)
    checks = {
        "length": abs(n - expect) <= 1 and 8.0 <= dur <= 16.0,
        "format": True,                                       # read_wav asserts mono / 22050 / 16-bit
        "ends_zero": abs(y[0]) < 0.001 and abs(y[-1]) < 0.001,
        "seam": seam_d2 <= 2.0 * d2_ref,
        "energy": abs(e_diff) <= 3.0,
        "loudness": abs(lufs - TARGET_LUFS) <= 0.3,
        "peak": peak <= -1.0 + 1e-6,
    }
    return dict(name=name, dur=dur, bars=spec["bars"], bpm=spec["bpm"], lufs=lufs, peak=peak, first=y[0], last=y[-1],
                seam=seam_d2, seam_ref=d2_ref, e_diff=e_diff, sub=sub, ok=all(checks.values()),
                failed=[k for k, v in checks.items() if not v])


def report(rows):
    print("%-20s %5s %4s %6s %8s %9s %8s %10s %8s %6s  %s" % (
        "file", "BPM", "bars", "len s", "LUFS", "peak dBFS", "first/last", "seam d2/ref", "start-end", "<80Hz", "result"))
    for r in rows:
        print("%-20s %5d %4d %6.2f %8.2f %9.2f %4.0e/%-4.0e %5.4f/%-5.4f %+7.2f dB %5.1f%%  %s" % (
            r["name"], r["bpm"], r["bars"], r["dur"], r["lufs"], r["peak"], abs(r["first"]), abs(r["last"]),
            r["seam"], r["seam_ref"], r["e_diff"], r["sub"], "PASS" if r["ok"] else "FAIL " + ",".join(r["failed"])))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        for n, s in TRACKS.items():
            print("%-20s %3d BPM  %d bars  %.1f s" % (n, s["bpm"], s["bars"], s["bars"] * 4 * 60.0 / s["bpm"]))
        print("emote_wheel_open      UI sound 0.15 s")
        return
    names = args or list(TRACKS) + ["emote_wheel_open"]
    if "--verify" not in sys.argv:
        for n in names:
            if n == "emote_wheel_open":
                write_wav(os.path.join(OUT, n + ".wav"), wheel_open())
                print("wrote", n)
                continue
            mix, _sq = build(TRACKS[n])
            master(mix, os.path.join(OUT, n + ".wav"), TRACKS[n].get("lpf"))
            print("wrote", n)
    rows = [verify(n) for n in names if n in TRACKS]
    report(rows)
    sys.exit(0 if all(r["ok"] for r in rows) else 1)


if __name__ == "__main__":
    main()
