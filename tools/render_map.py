#!/usr/bin/env python3
"""Render a twang Tiled map to a PNG preview (all visible tile layers,
true spritesheet art at the map's tile size, entities drawn as boxes).
Not part of the game: authoring/QA tool.

    python3 tools/render_map.py maps/meadow.json /tmp/meadow.png [scale]
    python3 tools/render_map.py maps/level1.json out.png 1 --terrain-only

Tile size and grid come from the map itself (8px terrain cells over the
256x256 spritesheet; 16px sprite-tileset cells are not drawn -- entity
boxes stand in for them, as in the 16px tool). `--terrain-only` skips
the entity boxes/labels (clean pixel-diff gate for terrain art).
"""

import json
import os
import re
import sys
from PIL import Image, ImageDraw

SHEET = os.path.join(os.path.dirname(__file__), "..", "spritesheet.png")


def parse_tsx(path):
    """Minimal .tsx reader: header + per-tile id (mirrors src/tiled.lua)."""
    with open(path) as f:
        xml = f.read()
    head = re.search(r'<tileset[^>]*>', xml)
    info = {}
    for k, v in re.findall(r'([\w_]+)\s*=\s*"([^"]*)"', head.group(0)):
        info[k] = int(v) if v.isdigit() else v
    tiles = {}
    xml = re.sub(r'<tile\s+id="(\d+)"[^>]*/>',
                 lambda m: '<tile id="%s"></tile>' % m.group(1), xml)
    for m in re.finditer(r'<tile\s+id="(\d+)"\s*(.*?)</tile>', xml, re.S):
        tid, body = int(m.group(1)), m.group(2)
        props = {}
        for p in re.finditer(r'<property\s+name="([^"]+)"[^>]*value="([^"]*)"', body):
            props[p.group(1)] = p.group(2)
        tiles[tid] = props
    return info, tiles


def render(map_path, out_path, scale=2, terrain_only=False):
    m = json.load(open(map_path))
    W, H = m['width'], m['height']
    TW, TH = m['tilewidth'], m['tileheight']
    tsx_dir = os.path.dirname(map_path)
    terrain = None
    chars_first = None
    for ref in m['tilesets']:
        info, tiles = parse_tsx(os.path.join(tsx_dir, ref['source']))
        if info['tilewidth'] == TW:
            terrain = (info, tiles, ref['firstgid'])
        elif chars_first is None:
            chars_first = ref['firstgid']
    cols = terrain[0]['columns']
    firstgid = terrain[2]
    sheet = Image.open(SHEET).convert('RGBA')

    out = Image.new('RGBA', (W*TW, H*TH), (135, 206, 235, 255))  # sky blue
    for layer in m['layers']:
        if layer['type'] != 'tilelayer' or not layer.get('visible', True):
            continue
        name = (layer.get('name') or '').lower()
        if name == 'background':
            continue
        data = layer['data']
        for i, gid in enumerate(data):
            if not gid or (chars_first and gid >= chars_first):
                continue
            t = gid - firstgid
            col, row = t % cols, t // cols
            tile = sheet.crop((col*TW, row*TH, (col+1)*TW, (row+1)*TH))
            x, y = i % W, i // W
            out.alpha_composite(tile, (x*TW, y*TH))
    # entity boxes + labels (16px art boxes, as in the 16px renderer)
    d = ImageDraw.Draw(out) if not terrain_only else None
    art = 16
    for layer in m['layers']:
        if terrain_only or layer['type'] != 'objectgroup' or not layer.get('visible', True):
            continue
        for o in layer.get('objects', []):
            props = {p['name']: p.get('value') for p in o.get('properties', [])}
            kind = (props.get('kind') or o.get('type') or o.get('class') or '?')
            x, y = o.get('x', 0), o.get('y', 0)
            w = o.get('width', 0) or (art if o.get('point') is None else 0)
            h = o.get('height', 0) or (art if o.get('point') is None else 0)
            if o.get('point'):
                w, h = art, art
                y -= art  # point objects: feet at the point
            colours = {'Spawn': (0, 228, 54), 'Room': (60, 60, 90),
                       'Exit': (255, 0, 77), 'Key': (255, 236, 39),
                       'Lock': (255, 163, 0), 'Door': (255, 119, 168),
                       'Switch': (255, 0, 77), 'Spring': (0, 228, 54),
                       'Archer': (255, 0, 77), 'Melee': (255, 0, 77),
                       'Laser': (255, 0, 77), 'Rocketeer': (255, 0, 77),
                       'Bomber': (255, 0, 77), 'Checkpoint': (0, 228, 54),
                       'Winch': (41, 173, 255)}
            col = colours.get(kind, (255, 0, 255))
            d.rectangle([x, y, x + w - 1, y + h - 1], outline=col + (255,))
            d.text((x + 1, y + 1), (o.get('name') or kind)[:6], fill=col + (255,))
    if scale != 1:
        out = out.resize((W*TW*scale, H*TH*scale), Image.NEAREST)
    out.save(out_path)
    print(f"{map_path} -> {out_path} ({W*TW*scale}x{H*TH*scale})")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    args = [a for a in sys.argv[1:] if a != '--terrain-only']
    render(args[0], args[1], int(args[2]) if len(args) > 2 else 2,
           terrain_only='--terrain-only' in sys.argv)
