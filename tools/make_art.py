#!/usr/bin/env python3
"""Forever's button art has one image level and no smaller ones. Shrunk to HUD size that would shimmer, and the client's
own UI textures all carry the full chain, so this writes them the same way: its header format, Forever's own pixels on
top, and each smaller level averaged from the one above.

    make_art.py    art/source/*.blp -> art/*.blp
"""
import os
import struct
from preview_atlas import read_dxt5

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def halve(width, height, pixels):
    """Box filter, weighting colour by alpha so transparent edges don't darken."""
    new_w, new_h = max(width // 2, 1), max(height // 2, 1)
    out = bytearray(new_w * new_h * 4)
    step_x, step_y = width // new_w, height // new_h
    for y in range(new_h):
        for x in range(new_w):
            total = [0, 0, 0]
            alpha = 0
            count = 0
            for dy in range(step_y):
                for dx in range(step_x):
                    o = ((y * step_y + dy) * width + x * step_x + dx) * 4
                    a = pixels[o + 3]
                    alpha += a
                    count += 1
                    for i in range(3):
                        total[i] += pixels[o + i] * a
            o = (y * new_w + x) * 4
            if alpha:
                out[o:o + 3] = bytes(total[i] // alpha for i in range(3))
            out[o + 3] = alpha // count
    return new_w, new_h, out


def to565(r, g, b):
    return ((r * 31 + 127) // 255) << 11 | ((g * 63 + 127) // 255) << 5 | ((b * 31 + 127) // 255)


def from565(c):
    return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31


def encode_block(block):
    """block: 16 (r, g, b, a). DXT5: endpoints from the block's range, each texel the nearest of the palette."""
    alphas = [p[3] for p in block]
    a0, a1 = max(alphas), min(alphas)
    if a0 == a1:
        alpha_bits = 0
    else:
        palette = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
        alpha_bits = 0
        for i, a in enumerate(alphas):
            best = min(range(8), key=lambda k: abs(palette[k] - a))
            alpha_bits |= best << (3 * i)
    solid = [p for p in block if p[3] > 0] or block
    lo = min(solid, key=lambda p: p[0] + p[1] + p[2])
    hi = max(solid, key=lambda p: p[0] + p[1] + p[2])
    c0, c1 = to565(*hi[:3]), to565(*lo[:3])
    if c0 < c1:
        c0, c1 = c1, c0
    code = 0
    if c0 != c1:
        p0, p1 = from565(c0), from565(c1)
        colors = [p0, p1, tuple((2 * x + y) // 3 for x, y in zip(p0, p1)), tuple((x + 2 * y) // 3 for x, y in zip(p0, p1))]
        for i, p in enumerate(block):
            best = min(range(4), key=lambda k: sum((colors[k][j] - p[j]) ** 2 for j in range(3)))
            code |= best << (2 * i)
    return bytes((a0, a1)) + alpha_bits.to_bytes(6, "little") + struct.pack("<HHI", c0, c1, code)


def encode(width, height, pixels):
    out = bytearray()
    for by in range(0, height, 4):
        for bx in range(0, width, 4):
            block = []
            for y in range(4):
                for x in range(4):
                    # Past the edge of a level smaller than a block: repeat the edge.
                    sx, sy = min(bx + x, width - 1), min(by + y, height - 1)
                    o = (sy * width + sx) * 4
                    block.append(tuple(pixels[o:o + 4]))
            out += encode_block(block)
    return bytes(out)


def build(name):
    source = os.path.join(ROOT, "art", "source", name + ".blp")
    raw = open(source, "rb").read()
    width, height, pixels = read_dxt5(source)
    offset, size = struct.unpack("<I", raw[20:24])[0], struct.unpack("<I", raw[84:88])[0]
    levels = [raw[offset:offset + size]]
    w, h, p = width, height, pixels
    while (w > 1 or h > 1) and len(levels) < 16:
        w, h, p = halve(w, h, p)
        levels.append(encode(w, h, p))
    head = b"BLP2" + struct.pack("<I4B2I", 1, 2, 8, 7, 1, width, height)
    offsets, sizes, at = [], [], 20 + 64 + 64 + 1024
    for level in levels:
        offsets.append(at)
        sizes.append(len(level))
        at += len(level)
    offsets += [0] * (16 - len(levels))
    sizes += [0] * (16 - len(levels))
    assert 20 + 64 + 64 + 1024 == 1172
    with open(os.path.join(ROOT, "art", name + ".blp"), "wb") as f:
        f.write(head + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + b"\0" * 1024 + b"".join(levels))
    print(name, width, height, len(levels), "levels", at, "bytes")


if __name__ == "__main__":
    for family in ("ltr", "shp", "rev", "gen"):
        build(family)
