#!/usr/bin/env python3
"""Generate 2D icons (gun icons, app icon, items) with a cheap OpenRouter image model.

    export OPENROUTER_API_KEY=...                  # never commit the key
    python3 tools/images/openrouter_generate.py --models          # image models, cheapest estimate first
    python3 tools/images/openrouter_generate.py --list            # assets this script can make
    python3 tools/images/openrouter_generate.py --test --cheapest # ONE image: check quality/cost first
    python3 tools/images/openrouter_generate.py --cheapest weapon_pistol app_icon
    python3 tools/images/openrouter_generate.py --model <id> --group weapons

See tools/images/README.md. Needs outbound access to openrouter.ai and ffmpeg. Standard library only.
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


class ApiError(Exception):
    def __init__(self, code, body):
        super().__init__("OpenRouter HTTP %d: %s" % (code, body))
        self.code, self.body = code, body


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
        raise ApiError(e.code, e.read().decode("utf-8", "replace")[:400])
    except urllib.error.URLError as e:
        sys.exit("cannot reach openrouter.ai (%s). Is the host allowed by the environment's network policy?" % e.reason)


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


# Output tokens billed for one ~1024x1024 image. OpenRouter lists only $/token (pricing.image_output),
# not tokens per image, so these are rough anchors (1 MP / 256 px for FLUX, ~200 for GPT Image, ~570 for
# Gemini Flash Image). The real cost is printed after every generation from the API's usage data.
TOKENS_PER_IMAGE = [("flux", 4096), ("gpt-image", 200), ("gemini", 570)]
DEFAULT_TOKENS = 1290


def est_cost(model_id, pricing):
    """Estimated $ per image, or None if the model does not report an output-image token price."""
    price = _num(pricing.get("image_output")) or _num(pricing.get("image_token"))
    if price <= 0:
        return None
    tokens = next((t for k, t in TOKENS_PER_IMAGE if k in model_id), DEFAULT_TOKENS)
    return price * tokens


def image_models():
    """[(est_$_per_image_or_None, id, name, output_modalities)], cheapest estimate first, unknown last."""
    rows = []
    for m in http("GET", API + "/models?output_modalities=image")["data"]:
        mods = m.get("architecture", {}).get("output_modalities") or []
        if "image" not in mods or m["id"].startswith("openrouter/"):  # routers have no fixed price
            continue
        rows.append((est_cost(m["id"], m.get("pricing", {})), m["id"], m.get("name", ""), mods))
    rows.sort(key=lambda r: (r[0] is None, r[0] or 0.0, r[1]))
    return rows


def pick_cheapest():
    rows = [r for r in image_models() if r[0] is not None]
    if not rows:
        sys.exit("no image models with a known price returned by OpenRouter")
    print("cheapest image model by estimated cost: %s (~$%.4f/image)" % (rows[0][1], rows[0][0]))
    return rows[0][1]


def generate_via_images(model, prompt, key):
    """Image-only models (GPT Image, FLUX, ...) use POST /images, not chat/completions."""
    resp = http("POST", API + "/images", key, {"model": model, "prompt": prompt, "n": 1})
    try:
        raw = base64.b64decode(resp["data"][0]["b64_json"])
    except (KeyError, IndexError, TypeError):
        sys.exit("no image in response: %s" % json.dumps(resp)[:400])
    return raw, (resp.get("usage") or {}).get("cost")


def generate(model, prompt, key):
    """Returns (image_bytes, cost_usd_or_None). Tries chat/completions, which Gemini-style models use;
    switches to /images when the API says the model needs it, and retries once with modalities=[image]."""
    payload = {"model": model, "usage": {"include": True},
               "messages": [{"role": "user", "content": prompt}]}
    try:
        resp = http("POST", API + "/chat/completions", key, dict(payload, modalities=["image", "text"]))
    except ApiError as e:
        if "/images" in e.body:
            return generate_via_images(model, prompt, key)
        if e.code not in (400, 404, 422):
            sys.exit(str(e))
        print("  first request failed (%s); retrying with modalities=[image]" % e.body[:160].replace("\n", " "))
        try:
            resp = http("POST", API + "/chat/completions", key, dict(payload, modalities=["image"]))
        except ApiError as e2:
            sys.exit(str(e2))
    try:
        msg = resp["choices"][0]["message"]
        url = msg["images"][0]["image_url"]["url"]
    except (KeyError, IndexError, TypeError):
        sys.exit("no image in response: %s" % json.dumps(resp)[:400])
    cost = (resp.get("usage") or {}).get("cost")
    m = re.match(r"data:image/[\w+.-]+;base64,(.*)", url, re.S)
    if m:
        return base64.b64decode(m.group(1)), cost
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read(), cost


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
        print("%-48s %-12s %-12s %s" % ("model", "est $/image", "outputs", "name"))
        for cost, mid, name, mods in image_models():
            print("%-48s %-12s %-12s %s" % (mid, "n/a" if cost is None else "%.4f" % cost, "+".join(mods), name))
        print("Estimates = output-image token price x assumed tokens per 1024px image; real cost is shown per image.")
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

    spent = 0.0
    for i, n in enumerate(todo, 1):
        print("[%d/%d] %s via %s" % (i, len(todo), n, model))
        raw, cost = generate(model, ASSETS[n]["prompt"], key)
        convert(raw, ASSETS[n], dest_of(n))
        spent += cost or 0.0
        print("  wrote %s (cost %s)" % (dest_of(n), "unknown" if cost is None else "$%.4f" % cost))
    print("spent $%.4f on %d image(s)." % (spent, len(todo)))
    print("done. Run tools/import_assets.sh, then look at the PNGs before committing them.")


if __name__ == "__main__":
    main()
