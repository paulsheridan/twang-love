#!/usr/bin/env python3
"""Draws the placeholder device art, so there is something on screen to
redraw.

Two outputs:

  * the 16x16 cells inside maps/chars.png -- spring (+spring_ext), key,
    lock, door, winch, gun, switch (+switch_on). Only those cells are
    rewritten; the player frames, HUD icons and enemy art in the same
    sheet are copied through untouched, so re-running is safe.
  * maps/drafts32.png + maps/drafts32.tsx -- updraft and outdraft at
    32x32, their own tileset because a Tiled sheet has one cell size. The
    game draws a cell larger than an entity's 16px block standing on the
    block's bottom edge (src/render/world.lua grounded_art), so the base
    of each sprite is the 16x16 block itself (rows 16-31, cols 8-23 of
    the cell) and the room above it is the launch the device promises.

Colours are the PICO-8 palette read straight out of src/palette.lua, so
the art cannot drift from the palette the game draws with.

Sprites are written as pixel grids ('.' transparent, 0-9a-f a palette
index) rather than drawn with primitives, because a placeholder you can
read and edit in the diff is the point. Every grid is checked against
its declared size on load, so a mistyped row is an error, not art.

usage:
    python3 tools/make_standins.py
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

CHARS_PNG = os.path.join(ROOT, "maps", "chars.png")
CHARS_TSX = os.path.join(ROOT, "maps", "chars.tsx")
DRAFTS_PNG = os.path.join(ROOT, "maps", "drafts32.png")
DRAFTS_TSX = os.path.join(ROOT, "maps", "drafts32.tsx")
PALETTE_LUA = os.path.join(ROOT, "src", "palette.lua")

CELL = 16
COLS = 16
BIG = 32

# chars.tsx local id -> the kind that tile declares. Read back from the
# file rather than hardcoded, so a renumber never silently repaints the
# wrong cell.
def chars_cell_for_kind():
    xml = open(CHARS_TSX).read()
    found = {}
    for m in re.finditer(r'<tile id="(\d+)">(.*?)</tile>', xml, re.S):
        k = re.search(r'name="kind" value="([^"]+)"', m.group(2))
        if k:
            found[k.group(1)] = int(m.group(1))
    return found


# ==== the 16x16 placeholders ====
# Palette notes: 0 black outline, 4/5 grey metal, 8 red, 9 orange,
# a yellow, b green, c blue, d purple.

SPRITES = {
    # a lever standing up, on its plate
    "switch": [
        "................",
        "................",
        "......0000......",
        "......0aa0......",
        "......0aa0......",
        ".....0aaaa0.....",
        ".....0aaaa0.....",
        "....0aaaaaa0....",
        "....0aaaaaa0....",
        "..0000000000....",
        "..0555555550....",
        "..0555555550....",
        "..0555555550....",
        "..0555555550....",
        "................",
        "................",
    ],
    # the same lever with its plate lit
    "switch_on": [
        "................",
        "................",
        "......0000......",
        "......0aa0......",
        "......0aa0......",
        ".....0aaaa0.....",
        ".....0aaaa0.....",
        "....0aaaaaa0....",
        "....0aaaaaa0....",
        "..0000000000....",
        "..0999999990....",
        "..0999999990....",
        "..0999999990....",
        "..0999999990....",
        "................",
        "................",
    ],
    # ring, stem, two teeth
    "key": [
        "................",
        ".....00000......",
        "....0999990.....",
        "...0990..090....",
        "...090....090...",
        "...090....090...",
        "....0900090.....",
        "......090.......",
        "......090.......",
        "......090.......",
        "......0990......",
        "......090.......",
        "......0990......",
        ".......090......",
        ".......00.......",
        "................",
    ],
    # padlock: shackle over a body with a keyhole
    "lock": [
        "................",
        ".....000000.....",
        "....0dddddd0....",
        "....0d....d0....",
        "....0d....d0....",
        "....0d....d0....",
        "...000dddd000...",
        "..099999999990..",
        "..099999999990..",
        "..099999999990..",
        "..0999dddd9990..",
        "..0999dddd9990..",
        "..0999dddd9990..",
        "..099999999990..",
        "..000000000000..",
        "................",
    ],
    # a door panel with a knob
    "door": [
        "................",
        "....000000......",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dd9dd90.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0dddddd0.....",
        "...0000000......",
        "................",
    ],
    # a compressed coil on its plate
    "spring": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "...0000000000...",
        "...0bbbbbbbb0...",
        "...0bbbbbbbb0...",
        "...0bbbbbbbb0...",
        "...0bbbbbbbb0...",
        "...0bbbbbbbb0...",
        "...0000000000...",
        "....0555550.....",
    ],
    # the same coil, drawn out
    "spring_ext": [
        "................",
        "................",
        "......0000......",
        "......0bb0......",
        "......0bb0......",
        "......0bb0......",
        "......0bb0......",
        "......0bb0......",
        "......0bb0......",
        "......0bb0......",
        "...0000bb0000...",
        "...0bbbbbbbb0...",
        "...0bbbbbbbb0...",
        "...0000000000...",
        "....0555550.....",
        "....0555550.....",
    ],
    # a drum with a rope running off to the left
    "winch": [
        "................",
        "................",
        ".....000000.....",
        "....09999990....",
        "....099bb990....",
        "....099bb990....",
        "....09999990....",
        "....09999990....",
        "....09999990....",
        "0...09999990....",
        "00..09999990....",
        "000.09999990....",
        "0.0000000000....",
        "................",
        "................",
        "................",
    ],
    # a dropped sidearm: body, muzzle at the right, grip below
    "gun": [
        "................",
        "................",
        "..0000000000....",
        "..0aaaaaaaa0c0..",
        "..0aaaaaaaa0c0..",
        "..0aaaaaaaa0c0..",
        "..0aaaaaaaa000..",
        "..0aaaaaaaa0....",
        "..0aaa0aaa0.....",
        "..0aa0.0aa0.....",
        "..00...0000.....",
        "......000.......",
        "................",
        "................",
        "................",
        "................",
    ],
}


# ==== the 32x32 devices ====
# Built rather than typed out: a 32-row grid of dots in the diff is
# unreadable, and the shape is simple (a plinth on the block, the launch
# above it).

OUTLINE, METAL, METAL_DARK, FLOW, ACCENT = "0", "5", "4", "c", "9"


def blank(size):
    return [[None] * size for _ in range(size)]


def put(grid, x, y, ch):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = ch


def rect(grid, x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(grid, x, y, ch)


def frame(grid, x0, y0, x1, y1, ch):
    for x in range(x0, x1 + 1):
        put(grid, x, y0, ch)
        put(grid, x, y1, ch)
    for y in range(y0, y1 + 1):
        put(grid, x0, y, ch)
        put(grid, x1, y, ch)


def line(grid, x0, y0, x1, y1, ch):
    """Bresenham, so a diagonal reads as one clean stroke."""
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    while True:
        put(grid, x0, y0, ch)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def chevron_up(grid, cx, top, half, ch):
    """A '^' of `half` steps, apex at (cx, top)."""
    for i in range(half + 1):
        put(grid, cx - i, top + i, ch)
        put(grid, cx + i, top + i, ch)


def device_base(grid):
    """The 16x16 plinth, drawn exactly over the block it stands on."""
    x0, y0, x1, y1 = 8, 16, 23, 31
    rect(grid, x0, y0, x1, y1, METAL)
    frame(grid, x0, y0, x1, y1, OUTLINE)
    # a shadowed lip along the bottom, and a lit lip along the top
    rect(grid, x0 + 1, y1 - 1, x1 - 1, y1 - 1, METAL_DARK)
    rect(grid, x0 + 1, y0 + 1, x1 - 1, y0 + 1, ACCENT)


def updraft_32():
    """A straight column: the launch rises from the plinth in one line."""
    g = blank(BIG)
    device_base(g)
    # vent slots in the plinth top
    for dx in (-4, 0, 4):
        rect(g, 16 + dx - 1, 18, 16 + dx, 20, OUTLINE)
    # three chevrons stacked up the middle, evenly spaced, the last one
    # stopping clear of the plinth's top edge
    for top in (1, 6, 11):
        chevron_up(g, 16, top, 3, FLOW)
        rect(g, 15, top + 4, 17, top + 4, FLOW)
    return g


def outdraft_32():
    """A funnel: the drain is thrown up-and-away, so the strokes splay
    off the plinth and open out into a hollow cone."""
    g = blank(BIG)
    device_base(g)
    for dx in (-4, 4):
        rect(g, 16 + dx - 1, 18, 16 + dx, 20, OUTLINE)
    # the cone's outer edge, opening upward from the plinth
    line(g, 12, 15, 7, 5, FLOW)
    line(g, 19, 15, 24, 5, FLOW)
    # and its inner edge, so the cone reads as hollow rather than as two
    # loose strokes
    line(g, 14, 15, 11, 9, FLOW)
    line(g, 17, 15, 20, 9, FLOW)
    return g


DEVICES = {"updraft": updraft_32, "outdraft": outdraft_32}


# ==== plumbing ====

def palette():
    """The PICO-8 palette, read from src/palette.lua."""
    src = open(PALETTE_LUA).read()
    body = src[src.index("Palette.COLOURS = {"):]
    cols = {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*(\d+),\s*(\d+),\s*(\d+)\s*\}",
                         body):
        cols[int(m.group(1))] = (int(m.group(2)), int(m.group(3)),
                                 int(m.group(4)))
    assert len(cols) == 16, "expected 16 palette entries, got %d" % len(cols)
    return cols


def check_grid(rows, size, what):
    assert len(rows) == size, \
        "%s: %d rows, expected %d" % (what, len(rows), size)
    for i, row in enumerate(rows):
        assert len(row) == size, \
            "%s: row %d is %d wide, expected %d (%r)" \
            % (what, i, len(row), size, row)
        for ch in row:
            assert ch == "." or ch in "0123456789abcdef", \
                "%s: row %d has %r, not a palette index" % (what, i, ch)


def stamp(img, grid, col, row, size):
    """Draws `grid` into cell (col, row) of an RGBA image, clearing the
    cell first: a placeholder that inherited the old art around its own
    pixels would read as a mistake."""
    cols = palette()
    for y in range(size):
        for x in range(size):
            px, py = col * size + x, row * size + y
            ch = grid[y][x]
            if ch is None or ch == ".":
                img.putpixel((px, py), (0, 0, 0, 0))
            else:
                r, g, b = cols[int(ch, 16)]
                img.putpixel((px, py), (r, g, b, 255))


def main():
    cells = chars_cell_for_kind()
    missing = sorted(set(SPRITES) - set(cells))
    assert not missing, "chars.tsx declares no tile for: %s" % ", ".join(missing)

    chars = Image.open(CHARS_PNG).convert("RGBA")
    assert chars.size == (COLS * CELL, 2 * CELL), \
        "expected a %dx%d chars sheet, got %dx%d" \
        % (COLS * CELL, 2 * CELL, chars.size[0], chars.size[1])

    for kind, rows in sorted(SPRITES.items()):
        check_grid(rows, CELL, kind)
        tid = cells[kind]
        stamp(chars, [[c for c in row] for row in rows],
              tid % COLS, tid // COLS, CELL)
        print("chars.png cell %2d  %s" % (tid, kind))
    chars.save(CHARS_PNG)

    big = Image.new("RGBA", (len(DEVICES) * BIG, BIG), (0, 0, 0, 0))
    for i, (kind, build) in enumerate(sorted(DEVICES.items())):
        grid = build()
        check_grid(["".join(c or "." for c in row) for row in grid],
                   BIG, kind)
        stamp(big, grid, i, 0, BIG)
        print("drafts32.png cell %d  %s" % (i, kind))
    big.save(DRAFTS_PNG)

    recs = []
    for i, kind in enumerate(sorted(DEVICES)):
        recs.append(
            ' <tile id="%d">\n'
            '  <properties>\n'
            '   <property name="kind" value="%s"/>\n'
            '  </properties>\n'
            ' </tile>\n' % (i, kind))
    tsx = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!-- Placeholder art for the big devices (tools/make_standins.py).\n'
        '     Its own tileset because a Tiled sheet has one cell size: the\n'
        '     16x16 devices live in chars.tsx. A cell larger than an\n'
        '     entity\'s 16px block is drawn standing on the block\'s bottom\n'
        '     edge, so the base of each sprite IS the block (rows 16-31,\n'
        '     cols 8-23) and the room above it is the launch. -->\n'
        '<tileset version="1.10" tiledversion="1.11.0" name="drafts32"'
        ' tilewidth="32" tileheight="32" tilecount="%d" columns="%d">\n'
        ' <image source="drafts32.png" width="%d" height="%d"/>\n'
    ) % (len(DEVICES), len(DEVICES), len(DEVICES) * BIG, BIG) + "".join(recs) \
        + "</tileset>\n"
    with open(DRAFTS_TSX, "w") as f:
        f.write(tsx)
    print("wrote %s and %s" % (DRAFTS_PNG, DRAFTS_TSX))


if __name__ == "__main__":
    sys.exit(main())
