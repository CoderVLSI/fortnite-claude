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
"""
import json
import os
import subprocess
import sys
import tempfile
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
    "car_horn": ("short double car horn honk", 0.8),
}
LOOPS = {   # looped ambience / engines: ElevenLabs supports a "loop" flag on newer models
    "engine_car_loop": ("steady idling dune buggy engine, seamless loop", 4.0),
    "storm_loop": ("low rumbling magical storm wall with crackling energy, seamless loop", 8.0),
    "ambient_loop": ("gentle outdoor wind over grass and distant birds, seamless loop", 10.0),
}


def request(path, payload, key):
    req = urllib.request.Request(API + path, data=json.dumps(payload).encode(), method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def to_wav(mp3_bytes, name):
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
        f.write(mp3_bytes)
        tmp = f.name
    dest = os.path.join(OUT, name + ".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ar", "22050", "-ac", "1", "-sample_fmt", "s16", dest], check=True)
    os.unlink(tmp)
    print("  wrote", dest)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    table = dict(SFX)
    table.update(LOOPS)
    if "--list" in sys.argv:
        for n, (p, s) in table.items():
            print("%-18s %.1fs  %s" % (n, s, p))
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
        payload = {"text": prompt, "duration_seconds": secs, "prompt_influence": 0.5}
        if n in LOOPS:
            payload["loop"] = True
        to_wav(request("/v1/sound-generation", payload, key), n)


if __name__ == "__main__":
    main()
