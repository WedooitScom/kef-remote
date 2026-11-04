"""Génère les icônes PNG de la PWA (sans dépendance : zlib + struct).

Motif : cercles concentriques évoquant le haut-parleur coaxial Uni-Q,
point cuivré au centre, sur fond quasi noir.

    uv run python scripts/make_icons.py
"""

import math
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "app" / "static" / "icons"

BG = (14, 14, 16)
RING = (58, 58, 64)
RING_LIGHT = (92, 92, 100)
COPPER = (214, 137, 80)


def blend(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def pixel(x, y, size, maskable):
    c = size / 2
    r = math.hypot(x + 0.5 - c, y + 0.5 - c) / (size / 2)  # 0 au centre, 1 au bord
    if maskable:
        r /= 0.8  # zone de sécurité des icônes "maskable"
    col = BG
    # Anneaux (rayon, demi-épaisseur, couleur), lissés sur ~1 px.
    aa = 1.5 / size
    for radius, half, color in ((0.74, 0.012, RING), (0.58, 0.07, RING_LIGHT), (0.40, 0.012, RING)):
        d = abs(r - radius) - half
        if d < aa:
            col = blend(color, col, max(0.0, d / aa))
    if r < 0.2 + aa:
        t = max(0.0, (r - 0.2) / aa)
        col = blend(blend(COPPER, (240, 180, 130), max(0.0, 1 - r / 0.2) * 0.35), col, t)
    return col


def png(size, maskable=False):
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            row.extend(pixel(x, y, size, maskable))
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size, maskable in (
        ("icon-192.png", 192, False),
        ("icon-512.png", 512, False),
        ("icon-maskable-512.png", 512, True),
        ("apple-touch-icon.png", 180, True),
    ):
        (OUT / name).write_bytes(png(size, maskable))
        print("écrit", OUT / name)
