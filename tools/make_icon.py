"""Write icon.png (storm-ring app icon) using only the standard library."""
import math
import os
import struct
import zlib

SIZE = 512
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def pixel(x, y):
    cx = cy = SIZE / 2
    d = math.hypot(x - cx, y - cy) / (SIZE / 2)
    t = y / SIZE
    r, g, b = 0.16 + 0.30 * t, 0.10 + 0.14 * t, 0.42 + 0.30 * t  # purple sky gradient
    if 0.62 < d < 0.72:  # storm ring
        r, g, b = 0.80, 0.55, 1.0
    elif d < 0.30:  # safe-zone dot
        r, g, b = 0.45, 0.90, 0.40
    elif 0.30 <= d < 0.33:
        r, g, b = 1.0, 1.0, 1.0
    a = 255 if d < 0.98 else 0
    return int(r * 255), int(g * 255), int(b * 255), a


raw = bytearray()
for y in range(SIZE):
    raw.append(0)
    for x in range(SIZE):
        raw.extend(pixel(x, y))


def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")
with open(os.path.join(ROOT, "icon.png"), "wb") as f:
    f.write(png)
print("wrote icon.png")
