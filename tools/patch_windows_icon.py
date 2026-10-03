#!/usr/bin/env python3
"""Put the game's icon into Godot's Windows export template (so exported .exe files show it).

Godot only embeds `application/icon` when it can run rcedit (Wine on Linux). On a box without Wine
this replaces the Godot-logo icons inside the *template* exe instead, which Godot then copies for
every export. Needs: pip install lief pillow.   Usage: tools/patch_windows_icon.py [icon.png] [template.exe]
"""
import io
import os
import shutil
import struct
import sys

import lief
from PIL import Image

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
icon_png = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "icon.png")
template_dir = os.path.expanduser("~/.local/share/godot/templates")
default = os.path.join(template_dir, "3.5.2.stable.custom_build", "windows_64_release.exe")
template = os.path.realpath(sys.argv[2] if len(sys.argv) > 2 else default)

backup = template + ".orig"
if not os.path.exists(backup):
    shutil.copy2(template, backup)          # always patch from the pristine template

binary = lief.PE.parse(backup)
art = Image.open(icon_png).convert("RGBA")
types = {c.id: c for c in binary.resources.childs}
icon_dir = types[3]                       # RT_ICON: one image per size
group_dir = types[14]                     # RT_GROUP_ICON: the table that lists them
group = group_dir.childs[0].childs[0]     # first (only) group, first language
table = bytearray(bytes(group.content))
count = struct.unpack_from("<H", table, 4)[0]
by_id = {}
for entry in icon_dir.childs:
    by_id[entry.id] = entry.childs[0]
for i in range(count):
    off = 6 + 14 * i
    width, height = table[off] or 256, table[off + 1] or 256
    icon_id = struct.unpack_from("<H", table, off + 12)[0]
    buf = io.BytesIO()
    art.resize((width, height), Image.LANCZOS).save(buf, format="PNG")       # PNG-compressed icon (Vista+)
    png = buf.getvalue()
    by_id[icon_id].content = png
    struct.pack_into("<I", table, off + 8, len(png))                          # dwBytesInRes
    struct.pack_into("<H", table, off + 4, 1)                                  # planes
    struct.pack_into("<H", table, off + 6, 32)                                 # bit count
group.content = bytes(table)

config = lief.PE.Builder.config_t()
config.resources = True
binary.write(template, config)

check = lief.PE.parse(template)
print("patched %s: %d icons, sizes %s" % (template, len(check.resources_manager.icons),
      sorted(i.width or 256 for i in check.resources_manager.icons)))
