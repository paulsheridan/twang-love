#!/usr/bin/env python3
"""Builds the 16px sprite tileset (characters & numbers).

The terrain tileset (maps/legacy/twang.tsx, rebuilt at 8x8 by
tools/build_tsx_8px.py) keeps only real-tile art: cells 96-103 (player
animation) and 128-170 (other characters and numbers) are never placed
as tiles, so they move out of the terrain vocabulary into their own
16x16 tileset. Because Tiled tilesets are rectangular grids over one
image, the sprite tileset covers sheet rows 6-10 (cells 96-175) -- the
smallest rectangle containing the reserved ranges -- backed by a
byte-exact copy of those rows in chars16.png (the sheet itself stays
untouched). Property records live only on the moved object kinds:

    local 41 (art 137) kind=archer
    local 42 (art 138) kind=laser
    local 44 (art 140) kind=melee
    local 47 (art 143) kind=bomber

Map objects reference this tileset at firstgid 1025 (right after the
terrain tileset's 1024 grid cells); art label = 96 + (gid - 1025).

usage:
    python3 tools/make_chars16.py     # writes maps/legacy/chars16.png + .tsx
"""
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SHEET = os.path.join(ROOT, "maps", "legacy", "spritesheet.png")
ATLAS = os.path.join(ROOT, "maps", "legacy", "chars16.png")
TSX = os.path.join(ROOT, "maps", "legacy", "chars16.tsx")

ROWS = range(6, 11)          # sheet rows 96..175
CHARS_BASE = 96              # art label of chars16 local id 0

KINDS = {137: "archer", 138: "laser", 140: "melee", 143: "bomber"}


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    w = struct.unpack(">I", data[16:20])[0]
    h = struct.unpack(">I", data[20:24])[0]
    depth, color = data[24], data[25]
    assert depth == 8 and color == 6, "expected 8-bit RGBA"
    idat = b""
    pos = 8
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        if typ == b"IDAT":
            idat += data[pos+8:pos+8+ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * 4 + 1
    img = bytearray(w * h * 4)
    prev = bytearray(w * 4)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p+stride-1])
        p += stride - 1
        for i in range(len(line)):
            a = line[i-4] if i >= 4 else 0
            b = prev[i]
            c = prev[i-4] if i >= 4 else 0
            if ft == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ft == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ft == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif ft == 4:
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        img[y*w*4:(y+1)*w*4] = line
        prev = line
    return w, h, img


def write_png(path, w, h, img):
    def chunk(typ, payload):
        return (struct.pack(">I", len(payload)) + typ + payload
                + struct.pack(">I", zlib.crc32(typ + payload) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    rows = b""
    stride = w * 4
    for y in range(h):
        rows += b"\x00" + bytes(img[y*stride:(y+1)*stride])
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(rows, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    w, h, img = read_png(SHEET)
    assert (w, h) == (256, 256)
    # rows 6..10 -> y 96..160
    crop = bytearray(256 * 80 * 4)
    for i, row in enumerate(ROWS):
        src = row * 256 * 4
        crop[i*256*4:(i+1)*256*4] = img[src:src + 256*4]
    write_png(ATLAS, 256, 80, crop)
    # verify byte-exact
    w2, h2, img2 = read_png(ATLAS)
    assert (w2, h2) == (256, 80)
    for i in range(len(crop)):
        assert crop[i] == img2[i], "atlas mismatch at byte %d" % i

    recs = []
    for art, kind in sorted(KINDS.items()):
        local = art - CHARS_BASE
        recs.append(
            ' <tile id="%d">\n'
            '  <properties>\n'
            '   <property name="kind" value="%s"/>\n'
            '  </properties>\n'
            ' </tile>\n' % (local, kind))
    tsx = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!-- twang sprite tileset: the character/number art the terrain\n'
        '     tileset reserves. Rectangular copy of spritesheet.png rows\n'
        '     6-10 (cells 96-175); local id = art label - 96. Maps place\n'
        '     these at firstgid 1025. Property records only on the object\n'
        '     kinds whose art moved out of the terrain tileset. -->\n'
        '<tileset version="1.10" tiledversion="1.11.0" name="twang-sprites"'
        ' tilewidth="16" tileheight="16" tilecount="80" columns="16">\n'
        ' <image source="chars16.png" width="256" height="80"/>\n'
    ) + "".join(recs) + "</tileset>\n"
    with open(TSX, "w") as f:
        f.write(tsx)
    print("wrote %s (256x80) and %s" % (ATLAS, TSX))


if __name__ == "__main__":
    sys.exit(main())
