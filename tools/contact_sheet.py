#!/usr/bin/env python3
"""Stitch the PNGs in a folder into one labelled contact sheet.  usage: contact_sheet.py DIR OUT.png [COLS] [W]"""
import os
import sys
from PIL import Image, ImageDraw

folder, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
width = int(sys.argv[4]) if len(sys.argv) > 4 else 480
files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
imgs = [Image.open(os.path.join(folder, f)).convert("RGB") for f in files]
w = width
h = int(imgs[0].height * w / imgs[0].width)
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(files, imgs)):
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(im.resize((w, h)), (x, y))
    d.rectangle([x, y, x + w, y + 18], fill=(0, 0, 0))
    d.text((x + 6, y + 3), f[:-4], fill=(255, 255, 255))
sheet.save(out)
print("wrote", out, sheet.size)
