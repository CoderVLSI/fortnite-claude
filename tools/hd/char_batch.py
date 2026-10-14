#!/usr/bin/env python3
"""Tries the Sketchfab candidates of each skin (tools/hd/characters.json) until one converts into a valid HD character.
   char_batch.py [skin ...]     (no args: every skin that has no hd/models/skin_<id>.glb yet)
A model is used for one skin only. Needs SKETCHFAB_API_TOKEN and Blender."""
import json, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import sketchfab
cands = json.load(open(os.path.join(HERE, "characters.json")))
used_file = os.path.join(HERE, "characters_used.json")
used = json.load(open(used_file)) if os.path.exists(used_file) else {}
want = sys.argv[1:] or list(cands)
REQ = {"Head", "Torso", "UpperL", "UpperR", "ForeL", "ForeR", "ShinL", "ShinR"}
for skin in want:
    out = os.path.join(ROOT, "hd", "models", "skin_%s.glb" % skin)
    if os.path.exists(out) and not sys.argv[1:]:
        continue
    done = False
    for c in cands.get(skin, []):
        if c["uid"] in used.values():
            continue
        work = tempfile.mkdtemp(prefix="hdc_", dir=os.environ.get("HD_WORK", "/tmp"))
        try:
            meta = sketchfab.get(c["uid"], work)
        except SystemExit as e:
            print(skin, c["uid"][:8], "download refused:", e)
            continue
        except Exception as e:
            print(skin, c["uid"][:8], "download failed:", e)
            continue
        src = next((os.path.join(work, f) for f in os.listdir(work) if f.endswith((".gltf", ".glb"))), None)
        if not src:
            continue
        tmp_out = os.path.join(work, "out.glb")
        r = subprocess.run(["blender", "-b", "-P", os.path.join(HERE, "character.py"), "--", src, tmp_out, "--tex", "512", "--tris", "14000"], capture_output=True, text=True)
        txt = r.stdout
        lab = "skeleton labelled: True" in txt
        m = re.search(r"CHAR parts (\{.*?\})", txt)
        parts = eval(m.group(1)) if m else {}
        ok = lab and REQ <= set(parts) and os.path.exists(tmp_out) and os.path.getsize(tmp_out) < 4_500_000
        print(skin, c["uid"][:8], c["name"][:30], "labelled" if lab else "NO-SKELETON", sorted(REQ - set(parts)) if parts else "no parts", "OK" if ok else "reject")
        if ok:
            shutil.copy(tmp_out, out)
            meta["replaces"] = "skin_" + skin
            os.makedirs(os.path.join(ROOT, "hd", "credits"), exist_ok=True)
            json.dump(meta, open(os.path.join(ROOT, "hd", "credits", "skin_%s.json" % skin), "w"), indent=1)
            used[skin] = c["uid"]
            json.dump(used, open(used_file, "w"), indent=1)
            done = True
        shutil.rmtree(work, ignore_errors=True)
        if done:
            break
    if not done:
        print(skin, "-> no valid candidate (stays pixel)")
