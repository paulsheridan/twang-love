#!/usr/bin/env python3
"""Builds love2d/spritesheet.png (256x256; a 16-column grid of 16x16 tiles)
from the
Kenney "Pico-8 Platformer" asset pack, which the twang.p8 cart art was
originally converted from. The tile->Kenney mapping was derived by exact
pixel matching against the cart's __gfx__ block and is frozen below, so
re-runs are deterministic.

The game runs at 16x16 tiles (src/config.lua tile_size), so every source
tile -- 8x8 in the pack and the cart -- is upscaled 2x2 on assembly: each
pixel becomes a 2x2 block and each tile slot is 16x16. Slot indices (the
16x16 grid) are unchanged, so tile ids and Tiled GIDs stay put.

Slots 0-127 preserve the cart-era layout: the Tiled map data (GIDs), the
tileset properties in maps/level1.json and the sprite constants in main.lua
all reference those indices. Slots 128-255 hold every Kenney tile not
already present (in ascending order), giving level editing the full pack
vocabulary; unused slots stay blank.

usage:
    python3 tools/import_kenney.py <kenney-pico8-platformer-dir> [out.png]

    python3 tools/import_kenney.py \\
      "/path/Kenney Game Assets All-in-1 3.4.0/2D assets/Pico-8 Platformer" \\
      spritesheet.png

Slot roles kept from the cart (hand-edited art with no exact counterpart):
  98           player down-aim pose
  101,102,103  player run-cycle frames 1-3
Enemy placement markers show the real enemy sprites:
  112 (archer) -> Kenney 85,  116 (melee) -> Kenney 148
"""
import sys, os
from PIL import Image

KENNEY_TILES = 150   # tiles in the pack (15x10 grid)
SHEET_SLOTS  = 256   # 16x16 tiles; the map format stores one tile per byte
SRC_TILE     = 8     # source tile size (px): pack tiles and the cart
TILE         = 16    # assembled tile size (px), 2x2 blocks of source pixels

# dedicated switch sprites: the switch kind tile is the OFF state (red
# lever); the ON state (green lever) lives in the next slot and is
# swapped in by the game when the switch is struck
SWITCH_OFF = [
    "........",
    "..8.....",
    "..6.....",
    "..66....",
    "..666...",
    ".dddddd.",
    ".dddddd.",
    "........",
]
SWITCH_ON = [
    "........",
    "....b...",
    "....6...",
    "...66...",
    "...666..",
    ".dddddd.",
    ".dddddd.",
    "........",
]
SWITCH_SLOT_OFF = 171
SWITCH_SLOT_ON  = 172

# game slot -> Kenney tile index ('P8' = keep the cart's own art)
MAPPING = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11, 12: 12, 13: 13, 14: 14, 15: 101, 16: 15, 17: 16, 18: 17, 19: 18, 20: 19, 21: 20, 22: 21, 23: 22, 24: 23, 25: 24, 26: 25, 27: 26, 28: 27, 29: 28, 30: 29, 31: 102, 32: 30, 33: 31, 34: 32, 35: 33, 36: 34, 37: 35, 38: 36, 39: 37, 40: 38, 41: 39, 42: 40, 43: 41, 44: 42, 45: 43, 46: 44, 47: 116, 48: 45, 49: 46, 50: 47, 51: 48, 52: 49, 53: 50, 54: 51, 55: 52, 56: 53, 57: 54, 58: 55, 59: 56, 60: 57, 61: 58, 62: 59, 63: 117, 64: 60, 65: 61, 66: 62, 67: 63, 68: 64, 69: 65, 70: 66, 71: 67, 72: 68, 73: 69, 74: 70, 75: 71, 76: 72, 77: 73, 78: 74, 79: 103, 80: 75, 81: 76, 82: 77, 83: 78, 84: 79, 85: 80, 86: 81, 87: 82, 88: 83, 89: 84, 90: 85, 91: 86, 92: 87, 93: 88, 94: 89, 95: 104, 96: 91, 97: 92, 98: 'P8', 99: 93, 100: 92, 101: 'P8', 102: 'P8', 103: 'P8', 104: 147, 105: 148, 106: 149, 107: 132, 108: 133, 109: 134, 110: 0, 111: 118, 112: 85, 113: 0, 114: 0, 115: 0, 116: 148, 117: 0, 118: 0, 119: 0, 120: 0, 121: 0, 122: 0, 123: 0, 124: 0, 125: 0, 126: 0, 127: 119}

# pico-8 palette (RGB), matching main.lua and the cart
PAL = [(0,0,0),(29,43,83),(126,37,83),(0,135,81),(171,82,54),
       (95,87,79),(194,195,199),(255,241,232),(255,0,77),(255,163,0),
       (255,236,39),(0,228,54),(41,173,255),(131,118,156),(255,119,168),
       (255,204,170)]
HEXCH = '0123456789abcdef'

def p8_sprite_grid(p8path, slot):
    """Extract a sprite as (char, opaque) where cart color 0 is transparent."""
    lines = open(p8path).read().splitlines()
    g0 = lines.index('__gfx__') + 1
    gfx = lines[g0:lines.index('__gff__')]
    r, c = slot // 16, slot % 16
    grid = []
    for i in range(SRC_TILE):
        row = []
        line = gfx[r * SRC_TILE + i] if r * SRC_TILE + i < len(gfx) else '0' * 128
        for j in range(SRC_TILE):
            ch = line[c * SRC_TILE + j]
            row.append((ch, ch != '0'))
        grid.append(row)
    return grid

def upscale(tile):
    """Upscale an SRC_TILE-sized tile to the game's TILE size (2x2 blocks)."""
    assert tile.size == (SRC_TILE, SRC_TILE), tile.size
    return tile.resize((TILE, TILE), Image.NEAREST)

def art_tile(rows):
    tile = Image.new('RGBA', (SRC_TILE, SRC_TILE), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                tile.putpixel((x, y), PAL[HEXCH.index(ch)] + (255,))
    return upscale(tile)

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    packdir, out = sys.argv[1], sys.argv[2]
    p8path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          '..', 'twang.p8')
    if not os.path.exists(p8path):
        sys.exit('cannot find twang.p8 next to the love2d dir: ' + p8path)

    tiles_dir = os.path.join(packdir, 'Transparent', 'Tiles')
    sheet = Image.new('RGBA', (16 * TILE, 16 * TILE), (0, 0, 0, 0))

    # slots 0-127: frozen cart-era layout
    for slot in range(128):
        dst = ((slot % 16) * TILE, (slot // 16) * TILE)
        src_idx = MAPPING[slot]
        if src_idx == 'P8':
            grid = p8_sprite_grid(p8path, slot)
            tile = Image.new('RGBA', (SRC_TILE, SRC_TILE), (0, 0, 0, 0))
            for y in range(SRC_TILE):
                for x in range(SRC_TILE):
                    ch, opaque = grid[y][x]
                    if opaque:
                        tile.putpixel((x, y), PAL[HEXCH.index(ch)] + (255,))
            tile = upscale(tile)
        else:
            tile = upscale(Image.open(
                os.path.join(tiles_dir, 'tile_%04d.png' % src_idx)).convert('RGBA'))
        sheet.paste(tile, dst)

    # slots 128+: every Kenney tile not already on the sheet, ascending
    used = {v for v in MAPPING.values() if v != 'P8'}
    missing = [i for i in range(KENNEY_TILES) if i not in used]
    assert 128 + len(missing) <= SHEET_SLOTS, 'extended tiles exceed 256 slots'
    for n, idx in enumerate(missing):
        dst = (((128 + n) % 16) * TILE, ((128 + n) // 16) * TILE)
        tile = upscale(Image.open(
            os.path.join(tiles_dir, 'tile_%04d.png' % idx)).convert('RGBA'))
        sheet.paste(tile, dst)
    sheet.paste(art_tile(SWITCH_OFF),
                ((SWITCH_SLOT_OFF % 16) * TILE, (SWITCH_SLOT_OFF // 16) * TILE))
    sheet.paste(art_tile(SWITCH_ON),
                ((SWITCH_SLOT_ON % 16) * TILE, (SWITCH_SLOT_ON // 16) * TILE))
    sheet.save(out)
    kept = sorted(s for s, v in MAPPING.items() if v == 'P8')
    print('wrote %s (%dx%d RGBA): 128 cart-layout slots, %d extended Kenney '
          'tiles in slots 128-%d (pack tiles %s), %d cart-kept slots %s'
          % (out, 16 * TILE, 16 * TILE, len(missing), 127 + len(missing),
             '%d-%d' % (missing[0], missing[-1]) if missing else 'none',
             len(kept), kept))

if __name__ == '__main__':
    main()
