#!/usr/bin/env python3
"""Raise targetSdkVersion in the stock Godot 3.5.x Android export templates.

Godot 3.5.2's prebuilt templates target API 32. Google Play Protect warns about / blocks
sideloaded apps whose target is more than two API levels below the phone's Android version
("Unsafe app blocked ... built for an older version of Android"). The compiled manifest is
binary XML, so we patch the int32 value of the targetSdkVersion attribute in place.

    tools/patch_android_target_sdk.py [TARGET] [templates_dir]    (default: 35)

Idempotent; keeps a .orig copy of each template the first time.
"""
import os
import shutil
import struct
import sys
import zipfile

TARGET = int(sys.argv[1]) if len(sys.argv) > 1 else 35
TEMPLATE_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/share/godot/templates/3.5.2.stable")


def string_index(data, wanted):
    """Index of `wanted` in the string pool of a binary AndroidManifest."""
    assert struct.unpack_from("<H", data, 0)[0] == 0x0003, "not a binary XML file"
    off = 8
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    assert ctype == 0x0001, "string pool expected first"
    count, _styles, flags, strings_start, _ = struct.unpack_from("<IIIII", data, off + 8)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from("<%dI" % count, data, off + 28)
    base = off + strings_start
    for i, o in enumerate(offsets):
        p = base + o
        if utf8:
            n = data[p]
            p += 1 if n < 0x80 else 2
            blen = data[p]
            p += 1 if blen < 0x80 else 2
            text = data[p:p + blen].decode("utf-8", "replace")
        else:
            n = struct.unpack_from("<H", data, p)[0]
            text = data[p + 2:p + 2 + n * 2].decode("utf-16le", "replace")
        if text == wanted:
            return i
    raise KeyError(wanted)


def patch_manifest(data):
    idx = string_index(data, "targetSdkVersion")
    # attribute record: ns, name, rawValue (int32 each), size=8 (u16), res0=0 (u8), type=0x10 (u8), data (int32)
    needle = struct.pack("<II", 0xFFFFFFFF, 0) [:0]
    out = bytearray(data)
    patched = 0
    pos = 0
    while True:
        pos = data.find(struct.pack("<I", idx), pos)
        if pos < 0:
            break
        # candidate: name idx at pos, preceded by ns int32, followed by rawValue int32, size/res/type, data
        try:
            raw, size, res0, dtype, value = struct.unpack_from("<iHBBi", data, pos + 4)
        except struct.error:
            break
        if size == 8 and res0 == 0 and dtype == 0x10 and 1 <= value <= 99:
            struct.pack_into("<i", out, pos + 4 + 4 + 2 + 1 + 1, TARGET)
            patched += 1
        pos += 4
    if not patched:
        raise RuntimeError("targetSdkVersion attribute not found")
    return bytes(out)


def patch_apk(path):
    backup = path + ".orig"
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    tmp = path + ".tmp"
    with zipfile.ZipFile(backup) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            blob = zin.read(item.filename)
            if item.filename == "AndroidManifest.xml":
                blob = patch_manifest(blob)
            zout.writestr(item, blob, compress_type=item.compress_type)
    os.replace(tmp, path)
    print("patched", path, "-> targetSdkVersion", TARGET)


for name in ("android_debug.apk", "android_release.apk"):
    p = os.path.join(TEMPLATE_DIR, name)
    if os.path.exists(p):
        patch_apk(p)
