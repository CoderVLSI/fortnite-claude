#!/usr/bin/env python3
"""Synthesise the "wanted" polish sounds: helicopter, ziplines, buried-chest dig, NPC hire, voice chat clicks, boss phase.

    python3 tools/audio/generate_polish_sfx.py                 # write every sound + its .wav.import
    python3 tools/audio/generate_polish_sfx.py heli_start      # just one
    python3 tools/audio/generate_polish_sfx.py --verify        # measure the files on disk
    python3 tools/audio/generate_polish_sfx.py --list

Needs numpy only, deterministic, no network, no API. Reuses the building blocks of generate_storm_island_sfx.py.
Output: mono, 44100 Hz, 16-bit PCM WAV, sample peak -3 dBFS, exact length (the format of docs/ASSET_REQUESTS.md for these items).
The two *_loop files are built from integer cycles, circular filtering and wrapped placement with no fades, so they
repeat without a click; Audio.gd loops every name that ends in _loop.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_storm_island_sfx import (OUT, PEAK_DB, SR, bell, bq, finish, harmonics, metal_hit, noise, periodic,  # noqa: E402
                                       put, ramp, read_wav, reverb, smooth, tt, write_import, write_wav, _pad)
from generate_weapon_extras_sfx import click, fit, mp, put_circ, sweep_sine  # noqa: E402

MAX_LEAD_S = 0.05
MAX_TAIL_S = 0.5
LOOP_S = 2.0


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ------------------------------------------------------------------ loops

def helicopter_loop():
    """2.0 s: 24 rotor beats (12 Hz blade pass) over a turbine whine; every frequency is a whole number of cycles in 2 s."""
    rng = np.random.default_rng(601)
    n = int(LOOP_S * SR)
    t = tt(n)
    beat = 0.5 + 0.5 * np.cos(2 * math.pi * 12 * t)                                       # 12 thumps per second
    thump = periodic(noise(rng, n), lambda x: bq(x, "lp", 240)) * beat ** 3 * 2.2
    body = np.sin(2 * math.pi * 36 * t) * beat ** 2 * 0.7                                  # chest-thump sub tone
    slap = periodic(noise(rng, n), lambda x: bq(x, "bp", 900, 0.8)) * beat ** 6 * 0.5      # blade slap, sharp on the beat
    wob = 1 + 0.08 * np.sin(2 * math.pi * 1 * t)
    whine = (np.sin(2 * math.pi * (1300 * t + (0.08 * 1300 / (2 * math.pi)) * (1 - np.cos(2 * math.pi * t))))
             + 0.35 * np.sin(2 * math.pi * 2600 * t) + 0.15 * np.sin(2 * math.pi * 3900 * t)) * 0.07 * wob
    air = periodic(noise(rng, n), lambda x: bq(x, "bp", 1800, 0.5)) * 0.08
    y = thump + body + slap + whine + air
    y = periodic(y, lambda x: bq(x, "lp", 7500))
    return finish(y, LOOP_S, loop=True)


def zipline_ride_loop():
    """2.0 s: pulley wheel whirring along a cable (18 Hz roll flutter), a singing cable tone and steady wind."""
    rng = np.random.default_rng(602)
    n = int(LOOP_S * SR)
    t = tt(n)
    flutter = 0.55 + 0.45 * np.abs(np.sin(2 * math.pi * 9 * t))                            # wheel revolutions, 18 per second
    whirr = periodic(noise(rng, n), lambda x: bq(bq(x, "bp", 2200, 1.4), "hp", 900)) * flutter * 0.9
    hum = (harmonics(150 * t, 9, 1.1) * flutter) * 0.14                                    # axle rumble, 150 Hz
    sing = (np.sin(2 * math.pi * (1420 * t + (0.012 * 1420 / (2 * math.pi)) * (1 - np.cos(2 * math.pi * t))))
            * (0.6 + 0.4 * np.sin(2 * math.pi * 1 * t)) * 0.05)                            # cable singing
    wind = periodic(noise(rng, n), lambda x: bq(x, "lp", 1200)) * (0.7 + 0.3 * np.sin(2 * math.pi * 2 * t + 0.6)) * 0.35
    y = whirr + hum + sing + wind
    for k in range(4):                                                                     # a few cable joints rattling past
        put_circ(y, 0.37 + 0.5 * k, click(rng, 3000, 0.006, 1.0), 0.8)
    y = periodic(y, lambda x: bq(x, "lp", 8000))
    return finish(y, LOOP_S, loop=True)


# ------------------------------------------------------------------ one-shots

def zipline_grab():
    rng = np.random.default_rng(603)
    n = int(0.4 * SR)
    t = tt(n)
    clack = mp(click(rng, 1800, 0.012, 1.0), metal_hit(900, 0.16, 61, 0.6) * 0.8)
    clack2 = mp(click(rng, 2600, 0.008, 0.7), metal_hit(1500, 0.1, 62, 0.5) * 0.5)
    y = fit(clack, n)
    put(y, 0.045, clack2, 0.6)
    zf = 2800 + 1800 * smooth(t / 0.18)                                                    # short rising cable zing
    zing = (np.sin(2 * math.pi * np.cumsum(zf) / SR) + 0.35 * np.sin(2 * math.pi * np.cumsum(zf * 1.51) / SR))
    zing *= smooth((t - 0.03) / 0.01) * np.exp(-np.maximum(t - 0.03, 0) / 0.09) * 0.2
    thud = sweep_sine(220, 90, n, 0.02) * np.exp(-t / 0.04) * 0.5
    y = (y + zing + thud) * ramp(n, 0.0004)
    return finish(y, 0.4, fade_out=0.1)


def heli_start():
    """2.5 s: turbine spooling up, the rotor thump slowing in from single beats to a steady chop."""
    rng = np.random.default_rng(604)
    n = int(2.5 * SR)
    t = tt(n)
    s = smooth(np.clip(t / 2.3, 0, 1))
    turb_f = 120 + 1180 * s ** 1.3                                                         # turbine whine climbs to 1.3 kHz
    ph = np.cumsum(turb_f) / SR
    whine = (np.sin(2 * math.pi * ph) + 0.35 * np.sin(4 * math.pi * ph) + 0.12 * np.sin(6 * math.pi * ph)) * smooth(t / 0.5) * 0.2
    rate = 1.0 + 10.5 * s ** 1.5                                                           # rotor beats per second, 1 -> 11.5
    beat_ph = np.cumsum(rate) / SR
    beat = 0.5 + 0.5 * np.cos(2 * math.pi * beat_ph)
    thump = bq(noise(rng, n), "lp", 230) * beat ** 3 * 2.0 * (0.25 + 0.75 * s)
    body = np.sin(2 * math.pi * 36 * t) * beat ** 2 * 0.6 * s
    slap = bq(noise(rng, n), "bp", 900, 0.8) * beat ** 6 * 0.5 * s
    air = bq(noise(rng, n), "bp", 1600, 0.5) * s ** 2 * 0.14
    start = bq(noise(rng, int(0.2 * SR)), "lp", 700) * np.exp(-tt(int(0.2 * SR)) / 0.04)    # starter ignition thud
    y = whine + thump + body + slap + air
    put(y, 0.0, start, 0.8)
    y = y + reverb(y, 0.4, 4000, 604, pre=0.005, length=0.3) * 0.15
    return finish(y, 2.5, fade_out=0.15)


def dig_dirt():
    rng = np.random.default_rng(605)
    n = int(0.5 * SR)
    t = tt(n)
    thud = sweep_sine(150, 55, n, 0.03) * np.exp(-t / 0.07) * 1.2                          # pickaxe lands in soil
    crunch = bq(noise(rng, n), "bp", 1500, 0.7) * np.exp(-t / 0.05) * 0.9
    soft = bq(noise(rng, n), "lp", 500) * np.exp(-t / 0.09) * 0.8
    y = (thud + crunch + soft) * ramp(n, 0.0005)
    for k, (t0, hz, g) in enumerate([(0.07, 2800, 0.5), (0.11, 2200, 0.4), (0.17, 3200, 0.3), (0.23, 2500, 0.22), (0.31, 3500, 0.15)]):
        put(y, t0, click(rng, hz, 0.012, 1.0), g)                                          # falling grit and pebbles
    sc = bq(noise(rng, int(0.25 * SR)), "bp", 2400, 0.9) * np.hanning(int(0.25 * SR)) * 0.25
    put(y, 0.12, sc)                                                                       # soil sliding off
    return finish(y, 0.5, fade_out=0.12)


def npc_hire():
    """1.0 s: handshake-style two-note "deal" jingle (G5 then C6) with a coin clink on top."""
    rng = np.random.default_rng(606)
    n = int(1.0 * SR)
    y = np.zeros(n)
    put(y, 0.0, bell(midi(79), 0.5, 0.17, 0.35), 0.8)
    put(y, 0.0, bell(midi(67), 0.5, 0.2, 0.2), 0.3)
    put(y, 0.2, bell(midi(84), 0.8, 0.24, 0.4), 1.0)
    put(y, 0.2, bell(midi(72), 0.8, 0.28, 0.2), 0.35)
    put(y, 0.2, bell(midi(76), 0.8, 0.26, 0.2), 0.25)
    for k, (t0, hz, g) in enumerate([(0.2, 4200, 0.8), (0.27, 5400, 0.6), (0.33, 4800, 0.45), (0.42, 6200, 0.3)]):
        put(y, t0, mp(metal_hit(hz, 0.12, 63 + k, 0.8) * 0.5, click(rng, 7000, 0.003, 0.3)), g)   # coins
    y = y + reverb(y, 0.5, 6000, 606, pre=0.008, length=0.5) * 0.25
    return finish(y, 1.0, fade_out=0.2)


def _voice_click(seed, rising):
    rng = np.random.default_rng(seed)
    n = int(0.15 * SR)
    t = tt(n)
    f = (1100 + 700 * smooth(t / 0.05)) if rising else (1800 - 700 * smooth(t / 0.05))
    tone = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.03) * 0.25              # faint "roger" chirp
    tick = click(rng, 2200, 0.004, 1.0)
    squelch = bq(noise(rng, n), "bp", 2400, 0.9) * np.exp(-t / (0.018 if rising else 0.05)) * 0.35
    y = fit(tick, n) * 0.9 + tone + squelch                                                # off keeps a little static tail
    return y * ramp(n, 0.0003)


def voice_on():
    return finish(_voice_click(607, True), 0.15, fade_out=0.04)


def voice_off():
    return finish(_voice_click(608, False), 0.15, fade_out=0.05)


def boss_phase():
    """1.5 s: a heavy hit, then a rising roar that peaks and cuts off for the phase change."""
    rng = np.random.default_rng(609)
    n = int(1.5 * SR)
    t = tt(n)
    y = np.zeros(n)
    put(y, 0.0, sweep_sine(110, 38, int(0.6 * SR), 0.06) * np.exp(-tt(int(0.6 * SR)) / 0.2) * 1.5)
    put(y, 0.0, bq(noise(rng, int(0.2 * SR)), "lp", 1400) * np.exp(-tt(int(0.2 * SR)) / 0.03), 0.9)
    put(y, 0.0, mp(click(rng, 1600, 0.01, 1.0), metal_hit(420, 0.35, 64, 0.8) * 0.8), 0.9)
    s = smooth(np.clip((t - 0.15) / 1.0, 0, 1))
    f = 70 + 200 * s ** 1.2                                                                # roar pitch rises
    ph = np.cumsum(f) / SR
    growl = harmonics(ph, 16, 1.0) * (0.6 + 0.4 * np.sin(2 * math.pi * (22 + 18 * s) * t))
    growl = np.tanh(growl * 1.8)
    growl = bq(growl, "lp", 600) * (1 - s) + bq(growl, "lp", 3800) * s                  # opens up as it rises
    nz = noise(rng, n)
    breath = (bq(nz, "bp", 700, 0.7) * (1 - s) + bq(nz, "bp", 2500, 0.7) * s) * 0.7
    env = smooth(np.clip((t - 0.1) / 0.55, 0, 1)) * (0.4 + 0.6 * s) * np.where(t < 1.38, 1.0, np.exp(-(t - 1.38) / 0.03))
    y += (growl * 0.8 + breath) * env
    y = y + reverb(y, 0.8, 3000, 609, pre=0.01, length=0.6) * 0.25
    return finish(y, 1.5, fade_out=0.06)


SOUNDS = {
    "helicopter_loop": (helicopter_loop, 2.0), "zipline_ride_loop": (zipline_ride_loop, 2.0),
    "zipline_grab": (zipline_grab, 0.4), "heli_start": (heli_start, 2.5), "dig_dirt": (dig_dirt, 0.5),
    "npc_hire": (npc_hire, 1.0), "voice_on": (voice_on, 0.15), "voice_off": (voice_off, 0.15),
    "boss_phase": (boss_phase, 1.5),
}
LOOPS = {"helicopter_loop", "zipline_ride_loop"}


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
