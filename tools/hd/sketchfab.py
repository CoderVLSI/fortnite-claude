#!/usr/bin/env python3
"""Sketchfab helper for the HD mode assets.

  sketchfab.py search "assault rifle" [--max-faces 20000] [--license cc0,by] [--count 8]
  sketchfab.py get <uid> <out_dir>        download the glTF zip, unpack it into out_dir, write out_dir/meta.json

Only CC0 and CC-BY models are used (credits are collected by credits.py). The API token comes from the environment
variable SKETCHFAB_API_TOKEN and is never printed or stored.
"""
import argparse, io, json, os, sys, urllib.request, urllib.parse, zipfile

API = "https://api.sketchfab.com/v3"
ALLOWED = {"cc0": "322a749bcfa841b29dff1e8a1bb74b0b", "by": "7c23a1ba438d4306920229c12afcb5f9"}   # Sketchfab licence uids


def _req(url, auth=False):
    r = urllib.request.Request(url, headers={"User-Agent": "storm-island-hd/1.0"})
    if auth:
        tok = os.environ.get("SKETCHFAB_API_TOKEN", "")
        if not tok:
            sys.exit("SKETCHFAB_API_TOKEN is not set")
        r.add_header("Authorization", "Token " + tok)
    return urllib.request.urlopen(r, timeout=60)


def search(q, max_faces=30000, licenses=("cc0", "by"), count=8, animated=False):
    out = []
    for lic in licenses:
        params = {"type": "models", "q": q, "downloadable": "true", "count": count, "sort_by": "-likeCount",
                  "max_face_count": max_faces, "license": lic}
        if animated:
            params["animated"] = "true"
        data = json.load(_req(API + "/search?" + urllib.parse.urlencode(params)))
        for m in data.get("results", []):
            out.append({"uid": m["uid"], "name": m["name"], "faces": m.get("faceCount"), "license": (m.get("license") or {}).get("slug", lic),
                        "author": (m.get("user") or {}).get("displayName", "?"), "likes": m.get("likeCount"), "url": m.get("viewerUrl")})
    return out


def get(uid, out_dir):
    info = json.load(_req(API + "/models/" + uid))
    lic = (info.get("license") or {}).get("slug", "")
    if lic not in ("cc0", "by"):
        sys.exit("refusing: licence '%s' is not CC0 / CC-BY" % lic)
    dl = json.load(_req(API + "/models/%s/download" % uid, auth=True))
    url = dl["gltf"]["url"]
    blob = _req(url).read()
    os.makedirs(out_dir, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(blob)).extractall(out_dir)
    meta = {"uid": uid, "name": info.get("name"), "author": (info.get("user") or {}).get("displayName"),
            "author_url": (info.get("user") or {}).get("profileUrl"), "license": lic, "license_label": (info.get("license") or {}).get("label"),
            "url": info.get("viewerUrl"), "faces": info.get("faceCount")}
    json.dump(meta, open(os.path.join(out_dir, "meta.json"), "w"), indent=1)
    return meta


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("q")
    s.add_argument("--max-faces", type=int, default=30000)
    s.add_argument("--license", default="cc0,by")
    s.add_argument("--count", type=int, default=8)
    s.add_argument("--animated", action="store_true")
    g = sub.add_parser("get")
    g.add_argument("uid")
    g.add_argument("out")
    a = ap.parse_args()
    if a.cmd == "search":
        for m in search(a.q, a.max_faces, tuple(a.license.split(",")), a.count, a.animated):
            print("%s  %-6s %6s faces  %-5s %s  by %s  (%s likes)" % (m["uid"], m["license"], m["faces"], "", m["name"], m["author"], m["likes"]))
    else:
        print(json.dumps(get(a.uid, a.out), indent=1))
