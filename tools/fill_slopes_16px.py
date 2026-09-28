#!/usr/bin/env python3
"""One-shot pre-migration fill of slope wedge tiles.

The game is removing slope collision (16px -> 8px tiles). Every slope
wedge cell in a map is replaced with a like-for-like solid:

    /\\floor (tiles 6,7,13,14) and plain ceils (61,62) -> solid tile 5
    sticky ceils (54,55)                    -> sticky solid tile 56

Runs BEFORE tools/migrate_maps_8px.py, on the 16px maps.
"""
import json
import glob
import os
import sys

FLOOR_SRC = {6, 7, 13, 14, 61, 62}
CEIL_STICKY_SRC = {54, 55}
# ground fill tiles (twang.tsx): solid / solid+sticky block art
FILL = 5
STICKY_FILL = 56

def migrate(path):
    with open(path) as f:
        m = json.load(f)
    changed = 0
    for layer in m.get('layers', []):
        if layer.get('type') != 'tilelayer':
            continue
        data = layer.get('data')
        if not data:
            continue
        n = len(data)
        for i in range(n):
            t = data[i]
            if t == 0:
                continue
            art = t - 1
            if art in FLOOR_SRC:
                data[i] = FILL + 1
                changed += 1
            elif art in CEIL_STICKY_SRC:
                data[i] = STICKY_FILL + 1
                changed += 1
    if not changed:
        return
    out = os.path.splitext(path)[0] + '_pre8.json'
    with open(out, 'w') as f:
        json.dump(m, f, separators=(',', ':'), ensure_ascii=False)
    print('%s: %d slope cells filled -> %s' % (path, changed, out))

def main():
    for path in sys.argv[1:] or sorted(glob.glob(os.path.join(
            os.path.dirname(__file__), '..', 'maps', '*.json'))):
        migrate(path)

if __name__ == '__main__':
    main()
