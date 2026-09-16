#!/usr/bin/env python3
"""One-shot migration of the twang Tiled maps from 8x8 to 16x16 tiles.

The game moved from 8x8 tiles to 16x16 tiles (src/config.lua tile_size 16,
spritesheet.png upscaled 2x2 by tools/upscale_sheet.py). The tile grid,
tile ids and Tiled GIDs are unchanged -- only the pixel size of a tile
doubled -- so each map needs:

  * tilewidth / tileheight: 8 -> 16
  * every object's x, y, width, height doubled (tile objects anchor at
    their bottom-left edge in Tiled, so scaling width/height together
    with the position keeps the game's anchor math consistent; rotations
    are multiples of 90 and rotate about the same relative anchor)

Everything else (layers, tile data, GIDs, properties, names) passes
through untouched. Maps are re-serialized with sorted keys off, matching
Tiled's own field ordering as closely as practical.

usage:
    python3 tools/migrate_maps_16px.py maps/level1.json [more.json ...]

  python3 tools/migrate_maps_16px.py maps/level1.json maps/level2.json
"""
import json
import os
import sys

OLD = 8
NEW = 16


def migrate(path):
    with open(path) as f:
        m = json.load(f)
    assert m.get('type') == 'map', path
    assert m['tilewidth'] == OLD and m['tileheight'] == OLD, (
        '%s is not an %dx%d map' % (path, OLD, OLD))

    m['tilewidth'] = NEW
    m['tileheight'] = NEW

    scaled = 0
    for layer in m.get('layers', []):
        if layer.get('type') != 'objectgroup':
            continue
        for o in layer.get('objects', []):
            if 'x' in o:
                o['x'] *= 2
            if 'y' in o:
                o['y'] *= 2
            if 'width' in o:
                o['width'] *= 2
            if 'height' in o:
                o['height'] *= 2
            for shape in ('polygon', 'polyline'):
                for pt in o.get(shape, []) or []:
                    pt['x'] *= 2
                    pt['y'] *= 2
            scaled += 1

    with open(path, 'w') as f:
        json.dump(m, f, separators=(',', ':'), ensure_ascii=False)
    print('%s: tile size %dx%d, %d objects rescaled'
          % (path, NEW, NEW, scaled))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        migrate(path)


if __name__ == '__main__':
    main()
