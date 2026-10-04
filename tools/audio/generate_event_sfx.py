#!/usr/bin/env python3
"""Synthesise the world / gadget / quest sound effects (no API, no credits, deterministic).

    python3 tools/audio/generate_event_sfx.py              # write all 16 to assets/audio/
    python3 tools/audio/generate_event_sfx.py thunder      # just one
    python3 tools/audio/generate_event_sfx.py --verify     # measure the files on disk
    python3 tools/audio/generate_event_sfx.py --list

Needs numpy (same as generate_audio.py). Reuses the oscillators / filters / instruments of
generate_emote_loops.py. Output: mono, 22050 Hz, 16-bit WAV, sample peak -3 dBFS, exact length.
rain_loop is built as a circular buffer with periodic filtering, so it loops without a click.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_emote_loops as E  # noqa: E402

SR = E.SR
OUT = E.OUT
PEAK_DB = -3.0


def tt(n):
    return np.arange(n) / SR


def put(buf, t, sig, gain=1.0):
    i = int(round(t * SR))
    if i >= len(buf):
        return
    k = min(len(sig), len(buf) - i)
    buf[i:i + k] += sig[:k] * gain


def finish(y, seconds, loop=False):
    n = int(round(seconds * SR))
    y = y[:n] if len(y) >= n else np.pad(y, (0, n - len(y)))
    y = y.copy()
    if not loop:
        a = int(0.001 * SR)
        y[:a] *= np.linspace(0, 1, a)
        k = int(0.006 * SR)
        y[-k:] *= np.linspace(1, 0, k)
    return y * (10 ** (PEAK_DB / 20) / np.max(np.abs(y)))


def formant(x, bands):
    return sum(g * E.bq(x, "bp", fc, q) for fc, q, g in bands)


def noise(rng, n):
    return rng.standard_normal(n)


# ------------------------------------------------------------------ weather

def rain_loop():
    rng = np.random.default_rng(101)
    n = 8 * SR
    base = E.periodic(noise(rng, n), lambda z: E.bq(E.bq(z, "hp", 1200), "lp", 8500))
    pts = rng.standard_normal(24)                              # slow level wobble, wraps by construction
    slow = np.interp(np.arange(n), np.linspace(0, n, 25), np.append(pts, pts[0]))
    base *= 1 + 0.12 * np.clip(slow, -2, 2)
    drops = E.Loop(n)
    for _ in range(8 * 380):                                  # leaf / grass patter
        k = int(rng.uniform(0.002, 0.007) * SR)
        drops.add(rng.integers(0, n), noise(rng, k) * np.exp(-np.arange(k) / (k / 3)), rng.uniform(0.05, 0.35))
    patter = E.periodic(drops.b, lambda z: E.bq(z, "hp", 2500))
    plinks = E.Loop(n)
    for _ in range(8 * 10):                                   # the odd bigger drop
        f, k = rng.uniform(1800, 4200), int(0.02 * SR)
        plinks.add(rng.integers(0, n), np.sin(2 * math.pi * f * tt(k)) * np.exp(-tt(k) / 0.006), rng.uniform(0.05, 0.15))
    mix = base * 0.5 + patter * 1.0 + plinks.b
    return finish(mix, 8.0, loop=True)


def thunder():
    rng = np.random.default_rng(102)
    n = int(3.5 * SR)
    t = tt(n)
    env = np.zeros(n)
    for t0, amp, att, dec in [(0.0, 1.0, 0.12, 0.55), (0.5, 0.8, 0.15, 0.8), (1.05, 0.7, 0.2, 0.9), (1.8, 0.45, 0.25, 0.9)]:
        u = np.clip((t - t0) / att, 0, 1)
        env += amp * (u * u * (3 - 2 * u)) * np.exp(-np.maximum(t - t0, 0) / dec) * (t >= t0)
    rumble = E.bq(noise(rng, n), "lp", 650) * env
    sub = np.sin(2 * math.pi * 55 * t) * (1 + 0.5 * np.sin(2 * math.pi * 6 * t)) * env * 0.3
    crack = E.bq(noise(rng, n), "bp", 1400, 0.8) * np.exp(-np.maximum(t - 0.03, 0) / 0.09) * (t >= 0.03) * 0.25
    y = E.bq(rumble * 3 + sub + crack, "lp", 1500)
    return finish(y * (1 - (t / 3.5) ** 3), 3.5)


# ------------------------------------------------------------------ traps, mines, bombs

def metal_hit(base=1800.0, dur=0.12):
    n = int(dur * SR)
    t = tt(n)
    y = sum(a * np.sin(2 * math.pi * base * r * t) * np.exp(-t / d)
            for r, a, d in [(1.0, 1.0, 0.03), (1.47, 0.6, 0.022), (2.09, 0.45, 0.016), (2.89, 0.3, 0.012)])
    return y * np.minimum(np.arange(n) / (0.0008 * SR), 1.0)


def trap_set():
    rng = np.random.default_rng(103)
    buf = np.zeros(int(0.3 * SR))
    thud = np.sin(2 * math.pi * np.cumsum(150 * (1 - 0.5 * (1 - np.exp(-tt(int(0.08 * SR)) / 0.03)))) / SR) \
        * np.exp(-tt(int(0.08 * SR)) / 0.035)
    click = E.bq(noise(rng, int(0.03 * SR)), "bp", 3500, 1.0) * np.exp(-tt(int(0.03 * SR)) / 0.004)
    for t0, g in [(0.0, 1.0), (0.075, 0.45), (0.13, 0.2)]:         # clack, then the plate settles
        put(buf, t0, metal_hit(1800, 0.12), g * 0.8)
        put(buf, t0, thud, g * 0.9)
        put(buf, t0, click, g * 0.8)
    return finish(buf, 0.3)


def spike_pop():
    rng = np.random.default_rng(104)
    buf = np.zeros(int(0.35 * SR))
    n = int(0.12 * SR)
    t = tt(n)
    f = 1800 * (7000 / 1800) ** (t / 0.12)                      # "shink": rising metal sweep
    shink = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.minimum(t / 0.004, 1) * np.exp(-t / 0.05) * 0.5
    shink += E.bq(noise(rng, n), "bp", 5000, 1.0) * np.minimum(t / 0.004, 1) * np.exp(-t / 0.045) * 0.8
    put(buf, 0.0, shink)
    put(buf, 0.065, metal_hit(4200, 0.1), 0.35)
    m = int(0.2 * SR)
    u = tt(m)                                                    # "thunk": low thump + wooden knock
    thunk = np.sin(2 * math.pi * np.cumsum(70 + 80 * np.exp(-u / 0.025)) / SR) * np.exp(-u / 0.07)
    thunk += E.bq(noise(rng, m), "lp", 700) * np.exp(-u / 0.03) * 0.7
    put(buf, 0.13, thunk * np.minimum(np.arange(m) / (0.001 * SR), 1), 1.0)
    put(buf, 0.13, metal_hit(1300, 0.12), 0.18)
    return finish(buf, 0.35)


def _beep(f, dur, w=0.5, rel=0.012):
    n = int(dur * SR)
    i = np.arange(n)
    return E.pulse(f, n, w) * np.minimum(i / (0.002 * SR), 1.0) * np.minimum((n - i) / (rel * SR), 1.0)


def mine_arm():
    buf = np.zeros(int(0.4 * SR))
    put(buf, 0.0, _beep(880, 0.12))
    put(buf, 0.17, _beep(1318.5, 0.2), 1.0)
    return finish(buf, 0.4)


def mine_beep():
    buf = np.zeros(int(0.15 * SR))
    put(buf, 0.0, _beep(1568, 0.11))
    return finish(buf, 0.15)


def boogie_pop():
    rng = np.random.default_rng(105)
    buf = np.zeros(int(0.8 * SR))
    E.RNG = np.random.default_rng(1051)
    put(buf, 0.0, E.d_kick(f0=95, f1=380, dec=0.05, dur=0.16, click=0.3, drive=1.3), 1.0)
    put(buf, 0.015, E.d_clap(), 0.55)
    for k, name in enumerate(["E6", "G6", "A6", "B6", "D7", "E7"]):     # rising pentatonic sparkle
        put(buf, 0.12 + 0.06 * k, E.i_bell(E.midi(name), int(0.04 * SR)), 0.28 + 0.07 * k)
    n = int(0.45 * SR)
    shimmer = E.bq(noise(rng, n), "hp", 7000) * np.minimum(tt(n) / 0.15, 1.0) * np.exp(-tt(n) / 0.16)
    put(buf, 0.12, shimmer, 0.18)
    return finish(buf, 0.8)


def stink_hiss():
    rng = np.random.default_rng(106)
    buf = np.zeros(int(1.2 * SR))
    n = int(0.8 * SR)
    t = tt(n)
    hiss = E.bq(E.bq(noise(rng, n), "hp", 3000), "lp", 9500)
    hiss *= np.minimum(t / 0.01, 1) * np.minimum((0.8 - t) / 0.14, 1) * (1 + 0.05 * np.sin(2 * math.pi * 3 * t))
    put(buf, 0.0, hiss, 0.8)
    put(buf, 0.0, E.bq(noise(rng, 200), "bp", 3000, 1.0) * np.exp(-tt(200) / 0.003), 0.8)   # canister tick
    m = int(0.4 * SR)
    u = tt(m)
    f0 = 40 * np.exp(-u / 0.25) + 18                                      # soft cartoon "pffft"
    am = 0.5 + 0.5 * np.sin(2 * math.pi * np.cumsum(f0) / SR)
    puff = E.bq(noise(rng, m), "bp", 900, 0.7) * (0.35 + 0.65 * am) * np.minimum(u / 0.02, 1) * np.exp(-u / 0.12)
    tone = np.sin(2 * math.pi * np.cumsum(130 - 40 * u / 0.4) / SR) * np.exp(-u / 0.1) * 0.2
    put(buf, 0.8, puff * 1.2 + tone, 0.8)
    return finish(buf, 1.2)


def _horn(f, dur, glide=0.0):
    n = int(dur * SR)
    t = tt(n)
    fr = f * (1 - glide * np.exp(-t / 0.03)) * (1 + 0.012 * np.sin(2 * math.pi * 6 * t))
    ph = 2 * math.pi * np.cumsum(fr) / SR
    y = sum(np.sin(k * ph) / k for k in range(1, 8))
    y = E.bq(y, "lp", 3200)
    i = np.arange(n)
    return y * np.minimum(i / (0.008 * SR), 1) * np.minimum((n - i) / (0.04 * SR), 1)


def llama_pop():
    rng = np.random.default_rng(107)
    buf = np.zeros(int(1.0 * SR))
    n = int(0.15 * SR)
    t = tt(n)
    put(buf, 0.0, E.bq(noise(rng, n), "bp", 1500, 0.5) * np.exp(-t / 0.05) * np.minimum(t / 0.0006, 1) * 1.0)   # burst
    put(buf, 0.0, np.sin(2 * math.pi * np.cumsum(60 + 90 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.09), 0.9)
    put(buf, 0.10, _horn(523, 0.09), 0.5)                                  # party horn: pa-PAAA
    put(buf, 0.22, _horn(784, 0.40, 0.06), 0.6)
    m = int(0.88 * SR)
    grains = np.zeros(m)
    for _ in range(140):                                                    # confetti rustle, thinning out
        p = int(m * (1 - rng.random() ** 0.6) ** 1.0)
        k = int(rng.uniform(0.002, 0.005) * SR)
        if p + k < m:
            grains[p:p + k] += np.exp(-np.arange(k) / (k / 3)) * rng.uniform(0.3, 1.0)
    put(buf, 0.12, E.bq(noise(rng, m), "hp", 3500) * grains, 0.55)
    return finish(buf, 1.0)


def reboot_van():
    rng = np.random.default_rng(108)
    buf = np.zeros(int(1.2 * SR))
    n = int(0.92 * SR)
    t = tt(n)
    f = 110 * 14 ** (t / 0.9)                                              # rising boot-up sweep
    ph = np.cumsum(f) / SR % 1.0
    sweep = (2 * ph - 1) * np.clip(t / 0.9, 0, 1) ** 1.5
    sweep *= 1 - 0.35 * (np.sin(2 * math.pi * 22 * t) > 0)                 # digital stutter
    sweep = E.bq(sweep, "lp", 5000) * np.minimum((0.92 - t) / 0.02, 1)
    put(buf, 0.0, sweep, 0.6)
    for k, fq in enumerate([660, 880, 1100]):
        put(buf, 0.12 + 0.12 * k, _beep(fq, 0.04, 0.5, 0.008), 0.35)
    put(buf, 0.95, E.i_bell(E.midi("E6"), int(0.06 * SR)), 0.9)               # ready ping
    return finish(buf, 1.2)


# ------------------------------------------------------------------ quests

def quest_accept():
    buf = np.zeros(int(0.5 * SR))
    put(buf, 0.0, E.i_bell(E.midi("G5"), int(0.07 * SR)), 0.8)                # ding
    put(buf, 0.19, E.i_epiano(E.midi("C5"), int(0.12 * SR)), 1.0)             # dum
    return finish(buf, 0.5)


def quest_complete():
    rng = np.random.default_rng(109)
    buf = np.zeros(int(0.9 * SR))
    for k, name in enumerate(["C6", "E6", "G6"]):
        put(buf, 0.09 * k, E.i_bell(E.midi(name), int(0.05 * SR)), 0.8)
    put(buf, 0.27, E.i_bell(E.midi("C7"), int(0.12 * SR)), 1.0)
    n = int(0.5 * SR)
    put(buf, 0.27, E.bq(noise(rng, n), "hp", 7500) * np.exp(-tt(n) / 0.12) * np.minimum(tt(n) / 0.01, 1), 0.16)
    for t0, name, g in [(0.31, "G7", 0.4), (0.37, "E7", 0.34), (0.43, "C8", 0.28), (0.50, "G7", 0.2)]:   # coin sparkle
        put(buf, t0, E.i_bell(E.midi(name), int(0.02 * SR)), g)
    return finish(buf, 0.9)


# ------------------------------------------------------------------ vehicles / water / animals

def pump_fill():
    rng = np.random.default_rng(110)
    buf = np.zeros(int(1.4 * SR))
    n = int(1.1 * SR)
    t = tt(n)
    pour = E.bq(noise(rng, n), "bp", 1200, 0.8) * np.minimum(t / 0.2, 1) * np.minimum((1.1 - t) / 0.08, 1)
    put(buf, 0.0, pour, 0.45)
    for _ in range(95):                                                      # bubbles, pitch rising as the tank fills
        t0 = 0.05 + 1.0 * rng.random() ** 0.8
        base = (260 + 520 * t0 / 1.1) * rng.uniform(0.8, 1.3)
        k = int(rng.uniform(0.012, 0.03) * SR)
        u = tt(k)
        b = np.sin(2 * math.pi * np.cumsum(base * (1 + 0.6 * u / u[-1])) / SR) * np.exp(-u / (k / SR / 3))
        put(buf, t0, b, rng.uniform(0.15, 0.5))
    m = int(0.26 * SR)
    u = tt(m)
    clunk = np.sin(2 * math.pi * np.cumsum(90 + 80 * np.exp(-u / 0.02)) / SR) * np.exp(-u / 0.07)
    clunk += E.bq(noise(rng, m), "lp", 900, 0.7) * np.exp(-u / 0.03) * 0.7
    clunk += (np.sin(2 * math.pi * 880 * u) + 0.6 * np.sin(2 * math.pi * 1370 * u)) * np.exp(-u / 0.06) * 0.2
    put(buf, 1.14, clunk * np.minimum(np.arange(m) / (0.001 * SR), 1), 1.2)
    return finish(buf, 1.4)


def chicken_cluck():
    rng = np.random.default_rng(111)
    buf = np.zeros(int(0.4 * SR))

    def cluck(dur, f0, fp, f1):
        n = int(dur * SR)
        t = tt(n)
        f = np.interp(t / dur, [0, 0.2, 1], [f0, fp, f1]) * (1 + 0.02 * np.sin(2 * math.pi * 47 * t))
        src = 2 * (np.cumsum(f) / SR % 1.0) - 1
        v = formant(src, [(850, 4, 1.0), (2300, 5, 0.6), (3600, 6, 0.2)])
        env = np.minimum(t / 0.006, 1) * np.exp(-t / 0.05)
        breath = E.bq(noise(rng, n), "bp", 2800, 1.2) * 0.12
        tick = E.bq(noise(rng, n), "bp", 2600, 1.5) * np.exp(-t / 0.004) * 0.7
        return (v * 0.5 + breath) * env + tick
    put(buf, 0.02, cluck(0.13, 520, 650, 340), 1.0)
    put(buf, 0.20, cluck(0.12, 470, 590, 310), 0.85)
    return finish(buf, 0.4)


def boar_grunt():
    rng = np.random.default_rng(112)
    buf = np.zeros(int(0.5 * SR))
    n = int(0.26 * SR)
    t = tt(n)
    f = np.interp(t / 0.26, [0, 0.3, 1], [105, 150, 82])
    src = 2 * (np.cumsum(f) / SR % 1.0) - 1
    g = formant(src, [(480, 2.5, 1.0), (1150, 3, 0.5)]) * (1 + 0.5 * np.sin(2 * math.pi * 30 * t))
    put(buf, 0.0, g * np.minimum(t / 0.05, 1) * np.exp(-t / 0.12), 1.0)
    for t0, dur, g0 in [(0.27, 0.07, 0.8), (0.36, 0.09, 0.7)]:               # snort: hnk-hnk
        m = int(dur * SR)
        u = tt(m)
        sn = E.bq(noise(rng, m), "bp", 1000, 1.2) + 0.25 * np.sin(2 * math.pi * 330 * u)
        put(buf, t0, sn * np.minimum(u / 0.008, 1) * np.exp(-u / 0.03), g0 * 0.9)
    return finish(buf, 0.5)


def out_of_fuel():
    rng = np.random.default_rng(113)
    buf = np.zeros(int(0.8 * SR))

    def putt(f, dur=0.13):
        n = int(dur * SR)
        t = tt(n)
        src = 2 * (np.cumsum(np.full(n, f)) / SR % 1.0) - 1
        body = E.bq(src, "lp", 1800) + 0.8 * E.pulse(f * 2, n, 0.3)
        pop = E.bq(noise(rng, n), "bp", 1400, 0.7) * np.exp(-t / 0.018) * 0.9
        return (body * np.exp(-t / 0.05) + pop) * np.minimum(t / 0.002, 1)
    for t0, g, f in [(0.0, 1.0, 150), (0.16, 0.85, 135), (0.34, 0.7, 118), (0.57, 0.5, 98)]:    # putt-putt-putt, slowing
        put(buf, t0, putt(f), g)
    m = int(0.22 * SR)
    u = tt(m)
    pff = E.bq(noise(rng, m), "bp", 1500, 0.6) * np.exp(-u / 0.07) * np.minimum(u / 0.008, 1)
    put(buf, 0.6, pff, 0.55)
    return finish(buf, 0.8)


SOUNDS = {
    "rain_loop": (rain_loop, 8.0), "thunder": (thunder, 3.5),
    "trap_set": (trap_set, 0.3), "spike_pop": (spike_pop, 0.35), "mine_arm": (mine_arm, 0.4),
    "mine_beep": (mine_beep, 0.15), "boogie_pop": (boogie_pop, 0.8), "stink_hiss": (stink_hiss, 1.2),
    "llama_pop": (llama_pop, 1.0), "reboot_van": (reboot_van, 1.2), "quest_accept": (quest_accept, 0.5),
    "quest_complete": (quest_complete, 0.9), "pump_fill": (pump_fill, 1.4), "chicken_cluck": (chicken_cluck, 0.4),
    "boar_grunt": (boar_grunt, 0.5), "out_of_fuel": (out_of_fuel, 0.8),
}


# ------------------------------------------------------------------ verification

def verify(name):
    path = os.path.join(OUT, name + ".wav")
    y = E.read_wav(path)                                   # asserts mono / 22050 Hz / 16-bit PCM
    want = SOUNDS[name][1]
    n = len(y)
    peak = 20 * math.log10(float(np.max(np.abs(y))) + 1e-12)
    rms = math.sqrt(float(np.mean(y * y)))
    loop = name.endswith("_loop")
    checks = {
        "length": abs(n / SR - want) <= 0.005,
        "peak": abs(peak - PEAK_DB) <= 0.1,
        "audible": rms > 0.01 and bool(np.all(np.isfinite(y))),
    }
    seam = ref = 0.0
    if loop:
        z = np.concatenate([y[-64:], y[:64]])
        seam = float(np.max(np.abs(np.diff(z, 2))))
        ref = float(np.percentile(np.abs(np.diff(y, 2)), 99.9))
        checks["seam"] = seam <= 2.0 * ref
    else:
        checks["ends_zero"] = abs(y[0]) < 0.01 and abs(y[-1]) < 0.01
    return dict(name=name, dur=n / SR, want=want, peak=peak, rms=20 * math.log10(rms), first=y[0], last=y[-1],
                seam=seam, ref=ref, loop=loop, ok=all(checks.values()), failed=[k for k, v in checks.items() if not v])


def report(rows):
    print("%-16s %6s %6s %9s %9s %11s  %s" % ("file", "want s", "len s", "peak dBFS", "rms dBFS", "first/last", "result"))
    for r in rows:
        extra = ("  seam d2 %.4f vs %.4f" % (r["seam"], r["ref"])) if r["loop"] else ""
        print("%-16s %6.2f %6.3f %9.2f %9.1f %5.3f/%-5.3f  %s%s" % (
            r["name"], r["want"], r["dur"], r["peak"], r["rms"], abs(r["first"]), abs(r["last"]),
            "PASS" if r["ok"] else "FAIL " + ",".join(r["failed"]), extra))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        for n, (_f, s) in SOUNDS.items():
            print("%-16s %.2f s" % (n, s))
        return
    names = args or list(SOUNDS)
    if "--verify" not in sys.argv:
        for n in names:
            E.write_wav(os.path.join(OUT, n + ".wav"), SOUNDS[n][0]())
            print("wrote", n)
    rows = [verify(n) for n in names]
    report(rows)
    sys.exit(0 if all(r["ok"] for r in rows) else 1)


if __name__ == "__main__":
    main()
