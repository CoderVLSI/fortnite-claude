#!/usr/bin/env python3
"""Fetch one Sketchfab model and turn it into an HD-mode asset.

  build_asset.py <name> <sketchfab_uid> [--tris N] [--tex PX] [--fit longest|volume] [--maps color|color+normal|all]

<name> is the pixel-mode model it replaces (res://assets/models/<name>.glb). Result: hd/models/<name>.glb (+ .import patched for embedded
materials) and hd/credits/<name>.json (author / licence, used by credits.py). Needs SKETCHFAB_API_TOKEN and Blender.
"""
import json, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import sketchfab

name, uid = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
ref = os.path.join(ROOT, "assets", "models", name + ".glb")
if not os.path.exists(ref):
    ref = os.path.join(HERE, "refs", name + ".glb")                  # a hand-made reference for things that have no pixel .glb (the helicopter)
if not os.path.exists(ref):
    sys.exit("no pixel model " + ref)
work = tempfile.mkdtemp(prefix="hd_" + name + "_", dir=os.environ.get("HD_WORK", "/tmp"))
meta = sketchfab.get(uid, work)
src = os.path.join(work, "scene.gltf")
if not os.path.exists(src):
    cands = [f for f in os.listdir(work) if f.endswith((".gltf", ".glb"))]
    src = os.path.join(work, cands[0])
out = os.path.join(ROOT, "hd", "models", name + ".glb")
r = subprocess.run(["blender", "-b", "-P", os.path.join(HERE, "normalize.py"), "--", src, ref, out] + extra, capture_output=True, text=True)
for line in r.stdout.splitlines():
    if line.startswith("NORMALIZE"):
        print(line)
if r.returncode != 0 or not os.path.exists(out):
    print(r.stdout[-1500:], r.stderr[-800:])
    sys.exit("blender failed")
os.makedirs(os.path.join(ROOT, "hd", "credits"), exist_ok=True)
meta["replaces"] = name
json.dump(meta, open(os.path.join(ROOT, "hd", "credits", name + ".json"), "w"), indent=1)
shutil.rmtree(work, ignore_errors=True)
print("OK %s <- %s by %s (%s) %.0f KB" % (name, meta["name"], meta["author"], meta["license"], os.path.getsize(out) / 1024))
