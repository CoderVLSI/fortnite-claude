#!/usr/bin/env python3
"""Writes docs/CREDITS_HD.md from hd/credits/*.json (every HD model: title, author, licence, link)."""
import glob, json, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(ROOT, "hd", "credits", "*.json")))]
out = ["# HD mode credits", "",
       "HD Mode uses 3D models from Sketchfab under CC0 or CC Attribution licences. Thank you to the authors. "
       "Each model was resized, re-oriented, simplified and had its textures reduced for this game.", "",
       "| Used for | Model | Author | Licence | Link |", "|---|---|---|---|---|"]
for r in rows:
    out.append("| %s | %s | [%s](%s) | %s | [Sketchfab](%s) |" % (r.get("replaces", ""), r.get("name", "").replace("|", "/"), r.get("author", "?"),
               r.get("author_url", ""), "CC0" if r.get("license") == "cc0" else "CC BY 4.0", r.get("url", "")))
open(os.path.join(ROOT, "docs", "CREDITS_HD.md"), "w").write("\n".join(out) + "\n")
print("credits for %d models" % len(rows))
