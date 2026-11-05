#!/usr/bin/env python3
"""Draws every button picture from lua/atlas.lua into one PNG, to check the table points at the right art.

    preview_atlas.py <out.png>
"""
import os
import re
import struct
import sys
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BUTTONS = ["SOUTH", "EAST", "WEST", "NORTH", "UP", "RIGHT", "DOWN", "LEFT", "LB", "RB", "LT", "RT", "START", "BACK", "L3", "R3"]
FAMILIES = ["ltr", "shp", "rev", "gen"]


def rgb565(c):
    return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31


def read_dxt5(path):
    data = open(path, "rb").read()
    width, height = struct.unpack("<II", data[12:20])
    offset = struct.unpack("<I", data[20:24])[0]
    pixels = bytearray(width * height * 4)
    at = offset
    for by in range(0, height, 4):
        for bx in range(0, width, 4):
            a0, a1 = data[at], data[at + 1]
            bits = int.from_bytes(data[at + 2:at + 8], "little")
            alphas = [a0, a1]
            if a0 > a1:
                alphas += [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
            else:
                alphas += [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
            c0, c1 = struct.unpack("<HH", data[at + 8:at + 12])
            code = struct.unpack("<I", data[at + 12:at + 16])[0]
            p0, p1 = rgb565(c0), rgb565(c1)
            colors = [p0, p1, tuple((2 * x + y) // 3 for x, y in zip(p0, p1)), tuple((x + 2 * y) // 3 for x, y in zip(p0, p1))]
            for y in range(4):
                for x in range(4):
                    i = y * 4 + x
                    r, g, b = colors[(code >> (2 * i)) & 3]
                    a = alphas[(bits >> (3 * i)) & 7]
                    o = ((by + y) * width + bx + x) * 4
                    pixels[o:o + 4] = bytes((r, g, b, a))
            at += 16
    return width, height, pixels


def main():
    text = open(os.path.join(ROOT, "lua", "atlas.lua")).read()
    art = {f: read_dxt5(os.path.join(ROOT, "art", f + ".blp")) for f in FAMILIES}
    cell = 64
    W, H = cell * len(BUTTONS), cell * len(FAMILIES)
    out = bytearray(b"\x28\x28\x30" * (W * H))
    for row, family in enumerate(FAMILIES):
        block = re.search(r"\t" + family + r" = \{\n(.*?)\n\t\},", text, re.S).group(1)
        for col, button in enumerate(BUTTONS):
            m = re.search(button + r' = \{ "(\w+)", ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+) \}', block)
            tex = art[m.group(1)]
            left, right, top, bottom = [float(m.group(i)) for i in range(2, 6)]
            for y in range(cell):
                sy = int(top * tex[1]) + y
                for x in range(cell):
                    sx = int(left * tex[0]) + x
                    o = (sy * tex[0] + sx) * 4
                    r, g, b, a = tex[2][o:o + 4]
                    d = ((row * cell + y) * W + col * cell + x) * 3
                    bg = out[d:d + 3]
                    out[d:d + 3] = bytes((r * a + bg[i] * (255 - a)) // 255 for i, (r) in enumerate((r, g, b)))
    raw = b"".join(b"\0" + bytes(out[y * W * 3:(y + 1) * W * 3]) for y in range(H))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    with open(sys.argv[1], "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    main()
