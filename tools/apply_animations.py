#!/usr/bin/env python3
"""
Repack exported Aseprite PNG strips into the game's spritesheet.

LÖVE cannot read .aseprite, so the animation work happens in Aseprite and
is exported as horizontal strips of 16x16 frames:

    animations/generated/player_animations.png   8 frames
    animations/generated/enemy_animations.png    3 frames
    animations/generated/world_animations.png    4 frames

This tool copies each frame back into the 256x256 sheet cell the game
already addresses by integer label, leaving every other cell untouched.
The game's label-based code (config.tiles, render/player.lua, the Tiled
maps) therefore needs no changes: cell 100 is still "run frame 1", it is
just now sourced from the exported strip.

    python3 tools/apply_animations.py            # write spritesheet.png
    python3 tools/apply_animations.py --check    # verify, change nothing

The mapping below must stay in step with the tags in the .aseprite files
(see tools/generate_aseprite.py) and with the state->cell mapping in
src/render/player.lua.
"""

import argparse
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "animations", "generated")
SHEET = os.path.join(ROOT, "spritesheet.png")

CELL = 16
COLS = 16

# strip name -> ordered list of sheet cell indices, one per frame.
#   player: idle, airborne, aim_down, landing, run 1..4  (render/player.lua:45-62)
#   enemy:  melee, archer, laser                        (config.tiles:609-611)
#   world:  switch off/on, spring collapsed/extended    (config.tiles:606-608)
STRIPS = {
    "player_animations": [96, 97, 98, 99, 100, 101, 102, 103],
    "enemy_animations":  [105, 90, 138],
    "world_animations":  [171, 172, 16, 32],
}


def read_strip(name):
    path = os.path.join(GEN, name + ".png")
    if not os.path.exists(path):
        return None, path
    im = Image.open(path).convert("RGBA")
    if im.height != CELL:
        raise SystemExit(f"{name}.png: expected height {CELL}, got {im.height}")
    if im.width % CELL:
        raise SystemExit(f"{name}.png: width {im.width} is not a multiple of {CELL}")
    return im, path


def cell_box(index):
    col, row = index % COLS, index // COLS
    return (col * CELL, row * CELL, col * CELL + CELL, row * CELL + CELL)


def collect():
    """Return [(cell_index, 16x16 RGBA Image), ...] from every strip."""
    frames = []
    for name, cells in STRIPS.items():
        im, path = read_strip(name)
        if im is None:
            print(f"  skip {name}.png (not exported yet)", file=sys.stderr)
            continue
        got = im.width // CELL
        if got != len(cells):
            raise SystemExit(
                f"{name}.png: has {got} frames but {len(cells)} cells are "
                f"mapped to it ({cells})"
            )
        for i, cell in enumerate(cells):
            frames.append((cell, im.crop((i * CELL, 0, (i + 1) * CELL, CELL))))
        print(f"  {name}.png: {got} frames -> cells {cells}")
    return frames


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="report whether the sheet is up to date, write nothing")
    args = ap.parse_args()

    if not os.path.exists(SHEET):
        raise SystemExit(f"missing {SHEET}")

    sheet = Image.open(SHEET).convert("RGBA")
    if sheet.size != (256, 256):
        raise SystemExit(f"{SHEET}: expected 256x256, got {sheet.size}")

    frames = collect()
    if not frames:
        raise SystemExit("no exported strips found; export the .aseprite files first")

    # Where does each cell currently stand?
    changed = []
    for cell, frame in frames:
        current = sheet.crop(cell_box(cell))
        if current.tobytes() != frame.tobytes():
            changed.append(cell)

    if args.check:
        if changed:
            print(f"OUT OF DATE: {len(changed)} cell(s) differ: {changed}")
            return 1
        print("up to date: sheet matches the exported strips")
        return 0

    for cell, frame in frames:
        sheet.paste(frame, cell_box(cell))

    sheet.save(SHEET)
    print(f"wrote {os.path.relpath(SHEET, ROOT)}: {len(frames)} cells updated "
          f"({len(changed)} differed from before)")
    if not changed:
        print("  note: exported art is currently identical to the existing cells")
    return 0


if __name__ == "__main__":
    sys.exit(main())
