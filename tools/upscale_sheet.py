#!/usr/bin/env python3
"""Upscales the twang spritesheet from 8x8 tiles to 16x16 tiles: every pixel
is doubled into a 2x2 block, so each 128x128 sheet (16x16 grid of 8x8 tiles)
becomes a 256x256 sheet with the same 16-column layout and tile ids. The
game runs at 16px tiles (see src/config.lua tile_size), so this makes the
sheet match the engine without touching any tile index.

usage:
    python3 tools/upscale_sheet.py [in.png] [out.png]

    python3 tools/upscale_sheet.py           # spritesheet.png in place
    python3 tools/upscale_sheet.py old.png new.png
"""
import os
import sys
from PIL import Image

TILE = 8    # source tile size (px)
SCALE = 2   # each source pixel becomes a SCALE x SCALE block


def upscale(src):
    w, h = src.size
    assert w == 16 * TILE and h == 16 * TILE, (
        'expected a %dx%d spritesheet, got %dx%d' % (16 * TILE, 16 * TILE, w, h))
    return src.resize((w * SCALE, h * SCALE), Image.NEAREST)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    inp = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'spritesheet.png')
    out = sys.argv[2] if len(sys.argv) > 2 else inp
    sheet = upscale(Image.open(inp).convert('RGBA'))
    sheet.save(out)
    w, h = sheet.size
    print('wrote %s (%dx%d RGBA: 256 tiles of 16x16, pixels 2x2)' % (out, w, h))


if __name__ == '__main__':
    main()
