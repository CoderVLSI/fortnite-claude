#!/usr/bin/env python3
"""Replace selected synthesised sounds with ElevenLabs-generated ones.

    export ELEVENLABS_API_KEY=...            # never commit the key
    python3 tools/audio/elevenlabs_generate.py --list
    python3 tools/audio/elevenlabs_generate.py --dry-run
    python3 tools/audio/elevenlabs_generate.py shot_rifle explosion   # just these
    python3 tools/audio/elevenlabs_generate.py                        # every sound below (spends credits)

Each result is converted with ffmpeg to 22.05 kHz mono WAV and written over assets/audio/<name>.wav
(the synthesised version stays reproducible with generate_audio.py). Afterwards run
tools/import_assets.sh. UNTESTED against the live API: the sandbox this was written in cannot reach it.
Needs outbound access to api.elevenlabs.io and ffmpeg.

Loops are cross-faded into a seamless join (loopify). music_bus uses the /v1/music endpoint, which needs a
PAID ElevenLabs plan (free plans get HTTP 402); without it the synthesised music stays in place. music_menu
(title/lobby) is a 20 s sound-generator music bed, so it works on the free plan.
`--loopify NAME...` re-applies the seam fix to an existing 16-bit mono WAV, spending no credits.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio"))
API = "https://api.elevenlabs.io"

# name -> (prompt, seconds)
SFX = {
    "shot_pistol": ("single 9mm pistol gunshot, outdoors, sharp crack with short echo", 1.0),
    "shot_smg": ("one submachine gun shot, tight and snappy, outdoors", 0.8),
    "shot_rifle": ("assault rifle single gunshot, punchy and loud, outdoor reverb tail", 1.5),
    "shot_shotgun": ("pump shotgun blast, heavy boom with long echo", 2.0),
    "shot_sniper": ("bolt action sniper rifle shot, huge crack and distant echo", 2.5),
    "shot_mythic": ("futuristic energy rifle shot, fiery boom with a bright rising shimmer", 2.0),
    "shot_mythic_pistol": ("huge futuristic hand cannon single shot, massive deep boom, bright metallic crack and a short sci-fi ring", 1.5),
    "shot_mythic_smg": ("futuristic submachine gun single shot, tight snappy electric crack with a high pitched hornet-like whine, short", 0.8),
    "shot_mythic_assault": ("futuristic assault rifle single shot with crackling lightning, punchy boom and an electric zap tail", 1.5),
    "shot_mythic_shotgun": ("fire-breathing shotgun blast, heavy boom with a roaring flame whoosh and crackling embers", 2.0),
    "reload": ("assault rifle reload: magazine out, magazine in, bolt slide", 1.6),
    "pump": ("shotgun pump action rack, two metallic clacks", 1.0),
    "explosion": ("large vehicle explosion, deep boom, debris and fire crackle", 3.0),
    "vehicle_crash": ("car crashing into a wall, metal crunch and impact", 1.2),
    "chest_open": ("wooden treasure chest creaking open with a magical chime", 1.5),
    "build_place": ("wooden building piece slammed into place, thud and clack", 0.7),
    "build_break": ("wooden wall smashed apart, splintering crunch", 1.2),
    "splash": ("person jumping into a lake, big water splash", 1.5),
    "storm_warn": ("ominous air raid style warning horn, two rising tones", 2.0),
    "hurt": ("short male pain grunt, game character hit", 0.6),
    "step_grass": ("single footstep of a person walking on grass, soft rustle, one step only", 0.5),
    "step_sand": ("single footstep on dry sand, soft crunchy scuff, one step only", 0.5),
    "step_wood": ("single footstep on a wooden floor, hollow thud, one step only", 0.5),
    "step_water": ("single footstep splashing in shallow water, one step only", 0.6),
    "glider_open": ("paraglider canopy snapping open, fabric whoomph and rush of air", 1.0),
    "jump": ("quick jump effort, short breath and shoe push-off, game character", 0.5),
    "land": ("person landing on the ground after a jump, soft thud with cloth rustle", 0.5),
    "death": ("game character defeated, short dramatic grunt then a body falling", 1.2),
    "hit_flesh": ("bullet impact on a body, dull meaty thud", 0.5),
    "hit_wood": ("bullet or pickaxe hitting wood, sharp thock", 0.5),
    "hit_stone": ("pickaxe hitting stone, sharp clink with rock chips", 0.5),
    "hit_metal": ("bullet hitting metal, ping and short ricochet", 0.6),
    "swing": ("pickaxe swing whoosh through the air", 0.5),
    "dry_fire": ("empty gun trigger click, dry fire", 0.5),
    "storm_hit": ("electric energy zap burning a player, magical storm damage", 0.8),
    "skid": ("car tyres skidding on dirt, short screech", 1.0),
    "swim_stroke": ("swimmer arm stroke through water, short splash", 0.6),
    "consume_bandage": ("applying a bandage, fabric rip and wrap", 1.2),
    "shield_up": ("magical energy shield charging up, rising shimmer", 1.0),
    "car_horn": ("short double car horn honk", 0.8),
}
LOOPS = {   # looped ambience / engines: ElevenLabs supports a "loop" flag on newer models
    "engine_car_loop": ("steady idling dune buggy engine, seamless loop", 4.0),
    "storm_loop": ("low rumbling magical storm wall with crackling energy, seamless loop", 8.0),
    "bus_loop": ("flying battle bus engine from outside, steady propeller drone with wind, seamless loop", 8.0),
    "glider_loop": ("paraglider gliding, steady soft rush of air over fabric canopy, seamless loop", 6.0),
    "wind_loop": ("strong wind rushing past during skydiving freefall, seamless loop", 6.0),
    "waves_loop": ("gentle ocean waves lapping on a shore, seamless loop", 8.0),
    "engine_quad_loop": ("steady idling quad bike engine, small and buzzy, seamless loop", 4.0),
    "engine_boat_loop": ("outboard motor boat engine idling on water, seamless loop", 4.0),
    "ambient_loop": ("gentle outdoor wind over grass and distant birds, seamless loop", 10.0),
}

# Title/lobby music made with the sound generator (works on the free plan): 20 s bed, equal-power
# cross-faded into a loop and normalised to the level of the other music tracks.
MUSIC_BEDS = {
    "music_menu": ("energetic electronic game lobby music, punchy synth bass, bright arpeggios, upbeat drums, "
                   "stormy sci-fi atmosphere, instrumental music, loopable", 20),
}
MUSIC_LUFS = -19.6

MUSIC = {   # /v1/music, instrumental (PAID plan only); each track is cross-faded into a seamless loop
    "music_bus": ("energetic instrumental for an airborne drop, driving drums, rising synth arpeggios, "
                  "anticipation and excitement, loopable", 30),
}


def request(path, payload, key):
    req = urllib.request.Request(API + path, data=json.dumps(payload).encode(), method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        hint = " (the music endpoint needs a paid ElevenLabs plan)" if e.code == 402 and path == "/v1/music" else ""
        sys.exit("ElevenLabs HTTP %d on %s%s: %s" % (e.code, path, hint, e.read().decode("utf-8", "replace")[:300]))


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         check=True, capture_output=True, text=True).stdout
    return float(out.strip())


def loopify(path, xf=1.0):
    """Cross-fade the last `xf` seconds into the first `xf` (equal power), so the file loops without a click.

    out = a[n:-n] + crossfade(a[-n:], a[:n]); the file is `xf` seconds shorter than the source.
    """
    import array
    import math
    import wave
    with wave.open(path, "rb") as w:
        rate, width, ch = w.getframerate(), w.getsampwidth(), w.getnchannels()
        a = array.array("h")
        a.frombytes(w.readframes(w.getnframes()))
    if width != 2 or ch != 1:
        sys.exit("loopify expects 16-bit mono WAV: " + path)
    if sys.byteorder == "big":
        a.byteswap()
    n = int(rate * xf)
    if len(a) < 4 * n:
        return
    out = a[n:-n]
    for i in range(n):
        t = (math.pi / 2) * i / (n - 1)
        v = a[len(a) - n + i] * math.cos(t) + a[i] * math.sin(t)
        out.append(max(-32768, min(32767, int(v))))
    if sys.byteorder == "big":
        out.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())


def set_loudness(path, target):
    """Apply one fixed gain so the integrated loudness equals `target` LUFS (peaks limited to -1 dBFS)."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    measured = float(re.findall(r"I:\s+(-?[\d.]+) LUFS", out)[-1])
    tmp = path + ".norm.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-af",
                    "volume=%gdB,alimiter=limit=0.89:level=disabled" % (target - measured), "-sample_fmt", "s16", tmp], check=True)
    os.replace(tmp, path)


RATES = {}


def to_wav(audio_bytes, name, rate=22050, loop=False, xf=1.0, lufs=None):
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
        f.write(audio_bytes)
        tmp = f.name
    dest = os.path.join(OUT, name + ".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ar", str(rate), "-ac", "1", "-sample_fmt", "s16", dest],
                   check=True)
    os.unlink(tmp)
    if loop:
        RATES[dest] = rate
        loopify(dest, xf)
    if lufs is not None:
        set_loudness(dest, lufs)
    print("  wrote", dest)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    table = dict(SFX)
    table.update(LOOPS)
    table.update(MUSIC_BEDS)
    table.update(MUSIC)
    if "--list" in sys.argv:
        for n, (p, s) in table.items():
            print("%-18s %.1fs  %s" % (n, s, p))
        return
    if "--loopify" in sys.argv:   # seam-fix existing loop files without spending credits
        for n in args:
            RATES[os.path.join(OUT, n + ".wav")] = 22050
            loopify(os.path.join(OUT, n + ".wav"))
            print("looped", n)
        return
    names = args or list(table)
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key and "--dry-run" not in sys.argv:
        sys.exit("set ELEVENLABS_API_KEY first")
    for n in names:
        prompt, secs = table[n]
        print(n, "->", prompt)
        if "--dry-run" in sys.argv:
            continue
        if n in MUSIC_BEDS:
            payload = {"text": prompt, "duration_seconds": secs, "prompt_influence": 0.6, "loop": True}
            to_wav(request("/v1/sound-generation", payload, key), n, rate=32000, loop=True, xf=2.0, lufs=MUSIC_LUFS)
            continue
        if n in MUSIC:
            payload = {"prompt": prompt, "music_length_ms": int(secs * 1000), "force_instrumental": True}
            to_wav(request("/v1/music", payload, key), n, rate=32000, loop=True, xf=2.0)
            continue
        payload = {"text": prompt, "duration_seconds": secs, "prompt_influence": 0.5}
        if n in LOOPS:
            payload["loop"] = True
        to_wav(request("/v1/sound-generation", payload, key), n, loop=n in LOOPS)


if __name__ == "__main__":
    main()
