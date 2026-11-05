"""Draws icon.png: a 128px rounded badge with a gamepad, in the style of the other repos' icons.

The glyph follows Tabler's "device-gamepad" (MIT). Pure Python, no image library: each pixel is sampled 4x4 against
distance functions. Usage: python3 tools/make_icon.py icon.png
"""
import math
import struct
import sys
import zlib

SIZE, SS = 128, 4
TOP, BOTTOM = (64, 112, 196), (30, 52, 108)  # gradient, top left to bottom right


def rounded_box(px, py, cx, cy, hw, hh, r):
    qx, qy = abs(px - cx) - hw + r, abs(py - cy) - hh + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def segment(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy or 1)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def glyph(px, py):
    """Distance to the gamepad strokes, in 24-unit icon space mapped onto the badge."""
    u, v = (px - 20) / 88 * 24, (py - 20) / 88 * 24
    scale = 88 / 24
    d = abs(rounded_box(u, v, 12, 12, 10, 6, 2))
    d = min(d, segment(u, v, 6, 12, 10, 12), segment(u, v, 8, 10, 8, 14))
    d = min(d, math.hypot(u - 15, v - 11), math.hypot(u - 18, v - 13))
    return d * scale


def pixel(x, y):
    color = [0.0, 0.0, 0.0, 0.0]
    for sy in range(SS):
        for sx in range(SS):
            px, py = x + (sx + 0.5) / SS, y + (sy + 0.5) / SS
            if rounded_box(px, py, 64, 64, 60, 60, 16) > 0:
                continue
            t = (px + py) / (2 * SIZE)
            rgb = [TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3)]
            if glyph(px, py) <= 1.0 * 88 / 24 / 2 + 0.6:  # stroke 2 of 24, like Tabler's outline icons
                rgb = [255, 255, 255]
            for i in range(3):
                color[i] += rgb[i]
            color[3] += 255
    n = SS * SS
    alpha = color[3] / n
    if alpha == 0:
        return (0, 0, 0, 0)
    return tuple(round(c / (color[3] / 255)) for c in color[:3]) + (round(alpha),)


def write_png(path, rows):
    raw = b"".join(b"\0" + bytes(v for p in row for v in p) for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


write_png(sys.argv[1], [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)])
