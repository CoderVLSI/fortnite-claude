#!/usr/bin/env python3
"""Generate 2D icons (gun icons, app icon, items) with a cheap OpenRouter image model.

    export OPENROUTER_API_KEY=...                  # never commit the key
    python3 tools/images/openrouter_generate.py --models          # image models, cheapest first
    python3 tools/images/openrouter_generate.py --list            # assets this script can make
    python3 tools/images/openrouter_generate.py --test --cheapest # ONE image: check quality/cost first
    python3 tools/images/openrouter_generate.py --cheapest weapon_pistol app_icon
    python3 tools/images/openrouter_generate.py --model <id> --group weapons

See tools/images/README.md. UNTESTED against the live API: the sandbox it was written in could not reach
openrouter.ai. Needs outbound access to openrouter.ai and ffmpeg. Standard library only.
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "icons")
API = "https://openrouter.ai/api/v1"

STYLE = ("flat vector game icon, bold clean outlines, bright saturated colours, subtle shading, "
         "playful battle-royale style, single object centred, no text, no watermark, ")
KEYED = "on a perfectly flat solid pure magenta (#FF00FF) background"
KEY_COLOUR = "0xFF00FF"

# name -> dict(prompt, size, group, key=True removes the magenta background, dest=override path)
ASSETS = {}


def add(name, group, prompt, size=128, key=True, dest=None):
    ASSETS[name] = {"group": group, "size": size, "key": key, "dest": dest, "prompt": prompt}


# Weapons: Items.WEAPONS keys, shown side-on, barrel pointing right.
for _n, _d in [
    ("pistol", "a compact semi-automatic pistol"),
    ("smg", "a submachine gun with a long curved magazine"),
    ("assault", "an assault rifle with a stock and a short magazine"),
    ("shotgun", "a pump-action shotgun with a wooden pump grip"),
    ("sniper", "a bolt-action sniper rifle with a scope"),
    ("pickaxe", "a heavy steel harvesting pickaxe with a wooden handle"),
]:
    add("weapon_" + _n, "weapons", "%sside view of %s, barrel pointing right, %s" % (STYLE, _d, KEYED))

for _n, _d in [
    ("light", "a small box of yellow pistol bullets"),
    ("medium", "a box of green rifle cartridges"),
    ("shells", "a few orange shotgun shells"),
    ("heavy", "a box of large blue sniper rounds"),
]:
    add("ammo_" + _n, "ammo", "%s%s, %s" % (STYLE, _d, KEYED))

for _n, _d in [
    ("bandage", "a rolled white bandage with a small red cross"),
    ("medkit", "a white first-aid medkit box with a red cross"),
    ("mini_shield", "a small glowing blue potion bottle"),
    ("shield_potion", "a large glowing blue shield potion flask"),
]:
    add("heal_" + _n, "items", "%s%s, %s" % (STYLE, _d, KEYED))

for _n, _d in [("wood", "a stack of wooden logs"), ("stone", "a pile of grey stones"), ("metal", "a stack of metal ingots")]:
    add("material_" + _n, "items", "%s%s, %s" % (STYLE, _d, KEYED))

# App icon. icon.png is project.godot's config/icon; the launcher_* files are for export_presets.cfg
# (see --wire-export). Adaptive icons keep the subject inside the centre 60 % (Android crops the rest).
_APP = "a glowing purple storm ring closing around a green safe-zone circle with a tiny pickaxe in the middle"
add("app_icon", "app", "mobile game app icon, %s, bold shapes, vivid purple and green, rounded-square artwork "
    "filling the whole canvas, no text" % _APP, size=512, key=False, dest=os.path.join(ROOT, "icon.png"))
add("launcher_main_192", "app", "mobile game app icon, %s, bold shapes, vivid purple and green, filling the whole "
    "canvas, no text" % _APP, size=192, key=False)
add("launcher_fg_432", "app", "game logo mark, %s, centred and small in the middle 60 percent of the canvas, %s"
    % (_APP, KEYED), size=432)
add("launcher_bg_432", "app", "abstract seamless dark purple to blue night-sky gradient with faint stars, "
    "no objects, no text", size=432, key=False)

GROUPS = sorted({a["group"] for a in ASSETS.values()})


def http(method, url, key=None, payload=None, timeout=180):
    headers = {"Content-Type": "application/json", "X-Title": "Storm Island assets"}
    if key:
        headers["Authorization"] = "Bearer " + key
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        sys.exit("OpenRouter HTTP %d: %s" % (e.code, body))
    except urllib.error.URLError as e:
        sys.exit("cannot reach openrouter.ai (%s). Is the host allowed by the environment's network policy?" % e.reason)


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def image_models():
    """[(price_per_image_or_None, completion_price, id, name)] of models that can output images."""
    rows = []
    for m in http("GET", API + "/models?output_modalities=image")["data"]:
        if "image" not in (m.get("architecture", {}).get("output_modalities") or []):
            continue
        p = m.get("pricing", {})
        rows.append((_num(p.get("image")), _num(p.get("completion")), m["id"], m.get("name", "")))
    # Cheapest first: by per-image price when the model has one, else by output-token price.
    rows.sort(key=lambda r: (r[0] if r[0] > 0 else 0.0, r[1]))
    return rows


def pick_cheapest():
    rows = [r for r in image_models() if r[2]]
    if not rows:
        sys.exit("no image-capable models returned by OpenRouter")
    r = rows[0]
    print("cheapest image model: %s (image $%.4f, completion $%.8f per token)" % (r[2], r[0], r[1]))
    return r[2]


def generate(model, prompt, key):
    resp = http("POST", API + "/chat/completions", key, {
        "model": model, "modalities": ["image", "text"],
        "messages": [{"role": "user", "content": prompt}]})
    try:
        msg = resp["choices"][0]["message"]
        url = msg["images"][0]["image_url"]["url"]
    except (KeyError, IndexError, TypeError):
        sys.exit("no image in response: %s" % json.dumps(resp)[:400])
    m = re.match(r"data:image/[\w+.-]+;base64,(.*)", url, re.S)
    if m:
        return base64.b64decode(m.group(1))
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def convert(raw, spec, dest):
    """Centre-crop to a square, scale to spec['size'], optionally key out the magenta background."""
    with tempfile.NamedTemporaryFile(suffix=".img", delete=False) as f:
        f.write(raw)
        tmp = f.name
    vf = ["crop='min(iw,ih)':'min(iw,ih)'", "format=rgba"]
    if spec["key"]:
        vf.append("colorkey=%s:0.30:0.08" % KEY_COLOUR)
    vf.append("scale=%d:%d:flags=lanczos" % (spec["size"], spec["size"]))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-vf", ",".join(vf), "-frames:v", "1", dest],
                   check=True)
    os.unlink(tmp)


def dest_of(name):
    return ASSETS[name]["dest"] or os.path.join(OUT, name + ".png")


def wire_export():
    """Point export_presets.cfg's launcher icons at the generated launcher_* files."""
    path = os.path.join(ROOT, "export_presets.cfg")
    text = open(path).read()
    for setting, name in [("main_192x192", "launcher_main_192"), ("adaptive_foreground_432x432", "launcher_fg_432"),
                          ("adaptive_background_432x432", "launcher_bg_432")]:
        if not os.path.exists(dest_of(name)):
            print("skip", setting, "(not generated yet)")
            continue
        text = re.sub(r'(launcher_icons/%s=)".*"' % setting, r'\1"res://assets/icons/%s.png"' % name, text)
        print("wired", setting, "->", name)
    open(path, "w").write(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="asset names (see --list); default: nothing, name something or use --group")
    ap.add_argument("--group", action="append", choices=GROUPS, help="generate a whole group")
    ap.add_argument("--model", help="OpenRouter model id")
    ap.add_argument("--cheapest", action="store_true", help="use the cheapest image model OpenRouter lists")
    ap.add_argument("--models", action="store_true", help="list image models, cheapest first, and exit")
    ap.add_argument("--list", action="store_true", help="list assets and exit")
    ap.add_argument("--test", action="store_true", help="generate only the first selected asset (default weapon_pistol)")
    ap.add_argument("--force", action="store_true", help="overwrite files that already exist")
    ap.add_argument("--max", type=int, default=12, help="refuse to generate more than this many images per run")
    ap.add_argument("--dry-run", action="store_true", help="print prompts and the plan, spend nothing")
    ap.add_argument("--wire-export", action="store_true", help="point export_presets.cfg at the launcher icons")
    a = ap.parse_args()

    if a.list:
        for n, s in ASSETS.items():
            print("%-20s %-8s %4dpx  %s" % (n, s["group"], s["size"], "(keyed)" if s["key"] else ""))
        return
    if a.wire_export:
        wire_export()
        return
    if a.models:
        for per_img, comp, mid, name in image_models():
            print("%-48s image $%-9.4f completion $%.8f/token  %s" % (mid, per_img, comp, name))
        return

    names = list(a.names)
    for g in a.group or []:
        names += [n for n, s in ASSETS.items() if s["group"] == g and n not in names]
    if a.test and not names:
        names = ["weapon_pistol"]
    bad = [n for n in names if n not in ASSETS]
    if bad or not names:
        sys.exit("unknown/no assets %s; see --list" % (bad or ""))
    if a.test:
        names = names[:1]
    todo = [n for n in names if a.force or not os.path.exists(dest_of(n))]
    for n in names:
        if n not in todo:
            print("skip", n, "(exists; --force to overwrite)")
    if len(todo) > a.max:
        sys.exit("%d images requested, over --max %d. Raise --max if that is intended." % (len(todo), a.max))

    key = os.environ.get("OPENROUTER_API_KEY", "")
    if a.dry_run:
        for n in todo:
            print(n, "->", ASSETS[n]["prompt"])
        print("%d image(s) would be generated" % len(todo))
        return
    if not key:
        sys.exit("set OPENROUTER_API_KEY first")
    model = a.model or (pick_cheapest() if a.cheapest else None)
    if not model:
        sys.exit("choose a model: --cheapest, or --model <id> (see --models)")

    for i, n in enumerate(todo, 1):
        print("[%d/%d] %s via %s" % (i, len(todo), n, model))
        convert(generate(model, ASSETS[n]["prompt"], key), ASSETS[n], dest_of(n))
        print("  wrote", dest_of(n))
    print("done. Run tools/import_assets.sh, then look at the PNGs before committing them.")


if __name__ == "__main__":
    main()
