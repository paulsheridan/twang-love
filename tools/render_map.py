#!/usr/bin/env python3
"""Render a twang Tiled map to a PNG preview (all visible tile layers,
true spritesheet art, entities drawn as boxes). Not part of the game:
authoring/QA tool for generated levels.

    python3 tools/render_map.py maps/meadow.json /tmp/meadow.png [scale]
"""

import json
import os
import sys
from PIL import Image

TSX = os.path.join(os.path.dirname(__file__), "..", "maps", "twang.tsx")
SHEET = os.path.join(os.path.dirname(__file__), "..", "spritesheet.png")
TW = 16

def parse_tsx(path):
    """Minimal .tsx reader: tile id -> properties (mirrors src/tiled.lua)."""
    import re
    with open(path) as f:
        xml = f.read()
    props = {}
    for m in re.finditer(r'<tile\s+id="(\d+)"\s*(.-)</tile>', xml, re.S):
        tid, body = int(m.group(1)), m.group(2)
        props = {}
        for p in re.finditer(r'<property\s+name="([^"]+)"[^>]*value="([^"]*)"', body):
            props[p.group(1)] = p.group(2)
        if props:
            tiles[tid + 1] = props
    return tiles

tiles = {}

def tile_props(gid):
    return tiles.get(gid, {})

def render(map_path, out_path, scale=2):
    m = json.load(open(map_path))
    W, H = m['width'], m['height']
    tsx_ref = m['tilesets'][0]
    tsx_dir = os.path.dirname(map_path)
    tsx_path = tsx_ref = tsx_ref.get('source') and os.path.join(tsx_dir, tsx_ref['source']) \
        or None
    if tsx_path and not tiles:
        parse_tsx(tsx_path)
    sheet = Image.open(SHEET).convert('RGBA')

    out = Image.new('RGBA', (W*TW, H*TW), (25, 25, 30, 255))
    for layer in m['layers']:
        if layer['type'] != 'tilelayer' or not layer.get('visible', True):
            continue
        name = (layer.get('name') or '').lower()
        data = layer['data']
        for i, gid in enumerate(data):
            if not gid:
                continue
            t = gid - 1
            r, c = divmod(t, 16)
            tile = sheet.crop((c*TW, r*TW, (c+1)*TW, (r+1)*TW))
            x, y = i % W, i // W
            if name == 'background':
                out.alpha_composite(tile, (x*TW, y*TW))
    # terrain after background
    for layer in m['layers']:
        if layer['type'] != 'tilelayer' or not layer.get('visible', True):
            continue
        name = (layer.get('name') or '').lower()
        if name == 'background':
            continue
        data = layer['data']
        for i, gid in enumerate(data):
            if not gid:
                continue
            t = gid - 1
            r, c = divmod(t, 16)
            tile = sheet.crop((c*TW, r*16 if False else r*TW, (c+1)*TW, (r+1)*TW))
            x, y = i % W, i // W
            out.alpha_composite(tile, (x*TW, y*TW))
    # entity boxes + labels
    d = ImageDraw = __import__('PIL.ImageDraw', fromlist=['ImageDraw']).Draw(out)
    for layer in m['layers']:
        if layer['type'] != 'objectgroup' or not layer.get('visible', True):
            continue
        for o in layer.get('objects', []):
            props = {p['name']: p.get('value') for p in o.get('properties', [])}
            kind = (props.get('kind') or o.get('type') or o.get('class') or '?')
            x, y = o.get('x', 0), o.get('y', 0)
            w = o.get('width', 0) or (TW if o.get('point') is None else 0)
            h = o.get('height', 0) or (TW if o.get('point') is None else 0)
            if o.get('point'):
                w, h = TW, TW
                y -= TW  # point objects: feet at the point
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
        out = out.resize((W*TW*scale, H*TW*scale), Image.NEAREST)
    out.save(out_path)
    print(f"{map_path} -> {out_path} ({W*TW*scale}x{H*TW*scale})")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    render(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 2)
