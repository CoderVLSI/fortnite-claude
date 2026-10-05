#!/usr/bin/env python3
"""Free, local (no API call) derivations for icons that must match another icon exactly. Needs Pillow.

    python3 tools/images/derive_icons.py zero-build    # assets/ui/ui_zero_build.png = ui_building.png + red slash
    python3 tools/images/derive_icons.py mythic-glow   # gold/purple glow behind assets/icons/weapon_*_mythic.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MYTHIC = ["tactical_shotgun", "revolver", "dmr", "grenade_launcher"]


def zero_build():
    """The wall piece with a bold diagonal red slash (dark navy outline so it reads on any background)."""
    src = os.path.join(ROOT, "assets", "ui", "ui_building.png")
    wall = Image.open(src).convert("RGBA")
    n = wall.width
    scale = 4                                           # draw 4x and downsample for a smooth edge
    layer = Image.new("RGBA", (n * scale, n * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a, b = (n * 0.14 * scale, n * 0.86 * scale), (n * 0.86 * scale, n * 0.14 * scale)   # bottom-left -> top-right
    d.line([a, b], fill=(18, 24, 58, 255), width=int(n * 0.17 * scale))               # outline
    d.line([a, b], fill=(235, 38, 38, 255), width=int(n * 0.11 * scale))              # red slash
    wall.alpha_composite(layer.resize((n, n), Image.LANCZOS))
    wall.save(os.path.join(ROOT, "assets", "ui", "ui_zero_build.png"), optimize=True)
    print("wrote assets/ui/ui_zero_build.png")


def glow(img, rgb, radius=7, strength=0.9, grow=5):
    """Soft glow behind an RGBA image. The icon stays inside its canvas, so the glow fades out before the edge."""
    a = img.getchannel("A")
    mask = a.filter(ImageFilter.MaxFilter(grow)).filter(ImageFilter.GaussianBlur(radius))
    g = Image.new("RGBA", img.size, rgb + (0,))
    g.putalpha(mask.point(lambda v: int(v * strength)))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(g)
    out.alpha_composite(img)
    return out


def mythic_glow():
    for n in MYTHIC:
        path = os.path.join(ROOT, "assets", "icons", "weapon_%s_mythic.png" % n)
        if not os.path.exists(path):
            print("skip", path, "(not generated)")
            continue
        img = Image.open(path).convert("RGBA")
        bb = img.getbbox()
        if bb:                                           # shrink to ~84 % of the canvas, centred, to leave glow room
            icon = img.crop(bb)
            s = 0.84 * img.width / max(icon.size)
            icon = icon.resize((max(1, round(icon.width * s)), max(1, round(icon.height * s))), Image.LANCZOS)
            img = Image.new("RGBA", img.size, (0, 0, 0, 0))
            img.alpha_composite(icon, ((img.width - icon.width) // 2, (img.height - icon.height) // 2))
        out = glow(img, (255, 200, 60))                  # gold
        out = glow(out, (150, 60, 255), radius=9, strength=0.55, grow=9)  # wider purple halo
        out.save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    {"zero-build": zero_build, "mythic-glow": mythic_glow}.get(cmd, lambda: sys.exit(__doc__))()
