#!/usr/bin/env python3
"""Synthesise the tactical shotgun / revolver / DMR / grenade-launcher sounds, the toggle clicks and the heal loops.

    python3 tools/audio/generate_weapon_extras_sfx.py              # write every sound + its .wav.import
    python3 tools/audio/generate_weapon_extras_sfx.py shot_dmr     # just one
    python3 tools/audio/generate_weapon_extras_sfx.py --verify     # measure the files on disk
    python3 tools/audio/generate_weapon_extras_sfx.py --list

Needs numpy only, deterministic, no network, no API. Reuses the building blocks of generate_storm_island_sfx.py.
Output: mono, 44100 Hz, 16-bit PCM WAV, sample peak -3 dBFS, exact length, no padding > 50 ms.
The two *_loop files are built from circular buffers (periodic filtering, wrapped placement) and no fades, so they
repeat without a click; Audio.gd loops every name that ends in _loop.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_storm_island_sfx import (OUT, PEAK_DB, SR, bq, finish, metal_hit, noise, periodic, put, ramp,  # noqa: E402
                                       read_wav, reverb, smooth, tt, write_import, write_wav, _pad)

MAX_PAD_S = 0.05            # leading silence limit (the sound must start at once)
MAX_TAIL_S = 0.25           # trailing near-silence: a natural decaying tail is fine, a long dead tail is not


def sweep_sine(f0, f1, n, tau):
    """Exponential pitch glide f0 -> f1 (time constant tau seconds), returned as a sine."""
    t = tt(n)
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(2 * math.pi * np.cumsum(f) / SR)


def mp(*sigs):
    """Sum signals of different lengths (zero-padded)."""
    y = np.zeros(max(len(x) for x in sigs))
    for x in sigs:
        y[:len(x)] += x
    return y


def fit(x, n):
    return x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))


def click(rng, hz, dur=0.01, gain=1.0):
    n = int(dur * SR * 4)
    return bq(noise(rng, n), "bp", hz, 1.5) * np.exp(-tt(n) / dur) * gain


def put_circ(buf, t, sig, gain=1.0):
    """Like put() but wraps around the end of the buffer (for seamless loops)."""
    i = int(round(t * SR)) % len(buf)
    idx = (i + np.arange(len(sig))) % len(buf)
    np.add.at(buf, idx, sig * gain)


# ------------------------------------------------------------------ weapon shots

def shot_tactical_shotgun():
    rng = np.random.default_rng(301)
    n = int(0.5 * SR)
    t = tt(n)
    crack = bq(noise(rng, n), "bp", 2800, 0.55) * np.exp(-t / 0.007) * 1.1
    body = bq(noise(rng, n), "lp", 1100) * np.exp(-t / 0.032)
    thump = sweep_sine(170, 62, n, 0.03) * np.exp(-t / 0.05) * 0.9
    dry = (crack + body * 0.9 + thump) * ramp(n, 0.0004)
    y = dry * 0.85 + reverb(dry, 0.14, 4500, 301, pre=0.004, length=0.16) * 0.5          # tight, dry little room
    rack = np.zeros(n)
    put(rack, 0.285, mp(click(rng, 1700, 0.008, 0.5), metal_hit(1500, 0.07, 3, 0.5) * 0.35))  # slide back
    put(rack, 0.285 + 0.035, bq(noise(rng, 600), "lp", 900) * np.exp(-tt(600) / 0.01) * 0.3)
    put(rack, 0.385, mp(click(rng, 2300, 0.007, 0.7), metal_hit(2100, 0.06, 4, 0.5) * 0.4))   # slide forward, locks
    return finish(y + rack * 0.55, 0.5, fade_out=0.02)


def shot_revolver():
    rng = np.random.default_rng(302)
    n = int(0.6 * SR)
    t = tt(n)
    crack = bq(noise(rng, n), "bp", 2200, 0.6) * np.exp(-t / 0.009) * 1.0
    body = bq(noise(rng, n), "lp", 1300) * np.exp(-t / 0.05)
    thump = sweep_sine(210, 70, n, 0.04) * np.exp(-t / 0.07) * 1.0
    ring = fit(metal_hit(1180, 0.5, 5, 1.0), n) * 0.28 * np.exp(-t / 0.18)                    # magnum ring
    dry = (crack + body * 0.8 + thump + ring) * ramp(n, 0.0004)
    echo = np.zeros(n)
    for d, g in [(0.075, 0.35), (0.15, 0.18)]:                                            # short metallic slap
        put(echo, d, bq(dry, "bp", 2400, 0.8), g)
    y = dry + echo * 0.8 + reverb(dry, 0.3, 3500, 302, pre=0.006, length=0.35) * 0.45
    return finish(y, 0.6, fade_out=0.06)


def shot_dmr():
    rng = np.random.default_rng(303)
    n = int(0.7 * SR)
    t = tt(n)
    crack = bq(bq(noise(rng, n), "hp", 1800), "bp", 4200, 0.45) * np.exp(-t / 0.0045) * 1.3
    snap = bq(noise(rng, n), "bp", 7000, 0.8) * np.exp(-t / 0.002) * 0.5
    mid = sweep_sine(300, 110, n, 0.025) * np.exp(-t / 0.045) * 0.9                       # mid-range thump
    body = bq(noise(rng, n), "lp", 1500) * np.exp(-t / 0.04) * 0.8
    dry = (crack + snap + mid + body) * ramp(n, 0.0003)
    y = dry + reverb(dry, 0.5, 3200, 303, pre=0.008, length=0.5) * 0.55
    return finish(y, 0.7, fade_out=0.15)


def shot_grenade_launcher():
    rng = np.random.default_rng(304)
    n = int(0.6 * SR)
    t = tt(n)
    pop = sweep_sine(190, 68, n, 0.045) * np.exp(-t / 0.09) * 1.0                         # hollow "thoonk"
    tube = bq(noise(rng, n), "bp", 260, 6.0) * np.exp(-t / 0.07) * 1.5                    # tube resonance
    puff = bq(noise(rng, n), "lp", 700) * np.exp(-t / 0.03) * 0.6
    y = (pop + tube + puff) * ramp(n, 0.0012)
    sp = tt(int(0.2 * SR))                                                                 # spring click then boing
    boing = np.sin(2 * math.pi * np.cumsum(900 + 260 * np.sin(2 * math.pi * 38 * sp)) / SR) * np.exp(-sp / 0.05) * 0.22
    spring = np.zeros(n)
    put(spring, 0.0, mp(click(rng, 3400, 0.004, 0.9), metal_hit(3000, 0.05, 6, 0.4) * 0.4))
    put(spring, 0.012, boing)
    y = y * 0.9 + spring * 0.45 + reverb(y, 0.25, 1800, 304, pre=0.004, length=0.3) * 0.35
    return finish(y, 0.6, fade_out=0.1)


# ------------------------------------------------------------------ weapon extras

def reload_revolver():
    rng = np.random.default_rng(305)
    n = int(1.2 * SR)
    y = np.zeros(n)
    # cylinder swings out: ratchet ticks + a little hinge whoosh
    for k in range(4):
        put(y, 0.05 + 0.028 * k, click(rng, 2400 + 150 * k, 0.005, 0.5))
    whoosh = bq(noise(rng, int(0.16 * SR)), "bp", 1500, 0.8)
    whoosh *= np.sin(np.pi * np.linspace(0, 1, len(whoosh))) ** 2
    put(y, 0.04, whoosh, 0.25)
    put(y, 0.2, metal_hit(900, 0.12, 7, 0.4), 0.3)
    # six rounds drop into the chambers
    for k in range(6):
        t0 = 0.34 + 0.085 * k + rng.uniform(-0.008, 0.008)
        base = rng.uniform(3200, 4800)
        put(y, t0, mp(metal_hit(base, 0.07, 20 + k, 0.6) * 0.45, click(rng, 2000, 0.006, 0.5)))
    # cylinder snaps shut: thump, then lock click
    thump = np.sin(2 * math.pi * np.cumsum(190 * np.exp(-tt(int(0.1 * SR)) / 0.02) + 85) / SR) * np.exp(-tt(int(0.1 * SR)) / 0.03)
    put(y, 0.985, thump, 0.8)
    put(y, 0.985, mp(click(rng, 2600, 0.008, 1.0), metal_hit(1700, 0.09, 8, 0.6) * 0.5))
    put(y, 1.03, click(rng, 3600, 0.005, 0.5))
    return finish(y + reverb(y, 0.2, 5000, 305, pre=0.003, length=0.2) * 0.25, 1.2, fade_out=0.08)


def grenade_launcher_bounce():
    rng = np.random.default_rng(306)
    n = int(0.3 * SR)
    t = tt(n)
    thud = sweep_sine(150, 62, n, 0.03) * np.exp(-t / 0.05)
    dull = bq(noise(rng, n), "lp", 650) * np.exp(-t / 0.022) * 0.8
    metal = fit(metal_hit(430, 0.25, 9, 0.3), n) * 0.25 * np.exp(-t / 0.07)                   # dull, damped metal body
    y = (thud + dull + metal) * ramp(n, 0.0006)
    put(y, 0.125, ((thud + dull) * 0.5)[:int(0.12 * SR)], 0.35)                         # the little second hop
    return finish(y, 0.3, fade_out=0.08)


# ------------------------------------------------------------------ UI

def _toggle(f0, f1, seed):
    rng = np.random.default_rng(seed)
    n = int(0.15 * SR)
    t = tt(n)
    f = f0 + (f1 - f0) * smooth(t / 0.05)
    tone = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.028)
    tone += 0.3 * np.sin(2 * math.pi * np.cumsum(f * 2) / SR) * np.exp(-t / 0.012)
    tick = bq(noise(rng, n), "bp", 3200, 1.0) * np.exp(-t / 0.0022) * 0.45               # soft switch tick
    return finish((tone * 0.8 + tick) * ramp(n, 0.0012), 0.15, fade_out=0.05)


def ui_toggle_on():
    return _toggle(820, 1450, 311)


def ui_toggle_off():
    return _toggle(1250, 620, 312)


# ------------------------------------------------------------------ heal loops (2.0 s, circular)

LOOP_S = 2.0


def consume_bandage_loop():
    """Wrapping a bandage: rhythmic cloth rustle with tape tugs; 5 strokes per loop."""
    rng = np.random.default_rng(321)
    n = int(LOOP_S * SR)
    t = tt(n)
    stroke = 0.45 + 0.55 * np.abs(np.sin(2 * math.pi * 2.5 * t))                         # 5 strokes in 2 s
    cloth = periodic(noise(rng, n), lambda x: bq(bq(x, "hp", 1400), "lp", 5200)) * stroke
    soft = periodic(noise(rng, n), lambda x: bq(x, "bp", 420, 0.7)) * stroke * 0.5
    y = cloth * 0.9 + soft
    for k in range(5):                                                                    # tape / cloth tug at stroke start
        tug = bq(noise(rng, int(0.05 * SR)), "bp", 2800, 1.2) * np.exp(-tt(int(0.05 * SR)) / 0.012)
        put_circ(y, 0.2 * k + 0.012, tug, 1.4)
    y = periodic(y, lambda x: bq(x, "lp", 7000))
    return finish(y, LOOP_S, loop=True)


def consume_potion_loop():
    """Drinking a potion: a steady run of glugs and small bubbles; 8 glugs per loop."""
    rng = np.random.default_rng(322)
    n = int(LOOP_S * SR)
    y = np.zeros(n)
    for k in range(8):
        d = int(0.15 * SR)
        f0 = 280 + 40 * (k % 3)
        glug = np.sin(2 * math.pi * np.cumsum(np.linspace(f0, f0 * 1.9, d)) / SR) * np.sin(np.pi * np.linspace(0, 1, d)) ** 1.5
        put_circ(y, 0.25 * k + 0.02, glug, 0.7 + 0.1 * (k % 2))
        for j in range(2):                                                                # little bubbles
            m = int(0.04 * SR)
            f1 = rng.uniform(900, 1700)
            b = np.sin(2 * math.pi * np.cumsum(np.linspace(f1, f1 * 1.5, m)) / SR) * np.exp(-tt(m) / 0.012)
            put_circ(y, 0.25 * k + rng.uniform(0.08, 0.22), b, 0.18)
    y += periodic(noise(rng, n), lambda x: bq(x, "bp", 2200, 0.8)) * 0.03
    return finish(y, LOOP_S, loop=True)


SOUNDS = {
    "shot_tactical_shotgun": (shot_tactical_shotgun, 0.5), "shot_revolver": (shot_revolver, 0.6),
    "shot_dmr": (shot_dmr, 0.7), "shot_grenade_launcher": (shot_grenade_launcher, 0.6),
    "reload_revolver": (reload_revolver, 1.2), "grenade_launcher_bounce": (grenade_launcher_bounce, 0.3),
    "ui_toggle_on": (ui_toggle_on, 0.15), "ui_toggle_off": (ui_toggle_off, 0.15),
    "consume_bandage_loop": (consume_bandage_loop, LOOP_S), "consume_potion_loop": (consume_potion_loop, LOOP_S),
}


# ------------------------------------------------------------------ verification

def verify(name):
    y, info = read_wav(os.path.join(OUT, name + ".wav"))
    want = SOUNDS[name][1]
    peak = 20 * math.log10(float(np.max(np.abs(y))) + 1e-12)
    rms = math.sqrt(float(np.mean(y * y)))
    lead, trail = _pad(y)
    loop = name.endswith("_loop")
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
        checks["pad"] = lead <= MAX_PAD_S and trail <= MAX_TAIL_S
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
