#!/usr/bin/env python3
"""Render a twang Tiled map to a PNG preview.

Not part of the game: an authoring/QA tool.

    python3 tools/render_map.py maps/roomgrid.json /tmp/roomgrid.png [scale]
    python3 tools/render_map.py maps/legacy/level1.json out.png 1 --terrain-only

Mirrors src/tiled.lua: a map may reference any number of tilesets, each
with its own image and geometry. 8x8 sets are TERRAIN (painted into the
grid, carrying the gameplay flags); 16x16 sets are ART (drawn from the
cell the author placed, or by the "kind" name for plain objects). Both
Tiled shapes are handled: a sheet (one <image>, tiles cut by source rect)
and a collection (every <tile> carrying its own <image>).

Object entities are outlined and labelled, so a level reads at a glance
even before the art exists. `--terrain-only` skips them entirely, which
makes a clean pixel-diff gate for terrain art.
"""

import json
import os
import re
import sys
from PIL import Image, ImageDraw

ART = 16
_cache = {}


def rooted(base_dir, source):
    """Resolve a .tsx's image source against the .tsx's own directory,
    collapsing '.' and '..' (mirrors rooted_path in src/tiled.lua)."""
    if source is None:
        return None
    if re.match(r'^[a-zA-Z]:[/\\]', source) or source.startswith('/'):
        return source                      # already absolute
    parts = []
    for part in os.path.join(base_dir, source).replace('\\', '/').split('/'):
        if part == '..':
            if parts:
                parts.pop()
        elif part and part != '.':
            parts.append(part)
    return '/'.join(parts)


def parse_tsx(path):
    """Minimal .tsx reader: header, image, per-tile properties and (for a
    collection) per-tile images. Mirrors parse_tsx in src/tiled.lua."""
    with open(path) as f:
        xml = f.read()
    tsx_dir = os.path.dirname(path)
    head = re.search(r'<tileset[^>]*>', xml)
    info = {}
    for k, v in re.findall(r'([\w_]+)\s*=\s*"([^"]*)"', head.group(0)):
        info[k] = int(v) if v.isdigit() else v
    img = re.search(r'<image[^>]*>', xml)
    info['image'] = None
    if img:
        a = dict(re.findall(r'([\w_]+)\s*=\s*"([^"]*)"', img.group(0)))
        info['image'] = rooted(tsx_dir, a.get('source', ''))
        info['imagewidth'] = int(a['width']) if 'width' in a else None
        info['imageheight'] = int(a['height']) if 'height' in a else None
    tiles = {}
    xml = re.sub(r'<tile\s+id="(\d+)"[^>]*/>',
                 lambda m: '<tile id="%s"></tile>' % m.group(1), xml)
    for m in re.finditer(r'<tile\s+id="(\d+)"\s*(.*?)</tile>', xml, re.S):
        tid, body = int(m.group(1)), m.group(2)
        props = {}
        for p in re.finditer(r'<property\s+name="([^"]+)"[^>]*value="([^"]*)"', body):
            props[p.group(1)] = p.group(2)
        timg = re.search(r'<image[^>]*>', body)
        tiles[tid] = {'props': props,
                      'image': rooted(tsx_dir, dict(
                          re.findall(r'([\w_]+)\s*=\s*"([^"]*)"',
                                     timg.group(0))).get('source', ''))
                      if timg else None}
    info['tiles'] = tiles
    # a collection has per-tile images and no sheet of its own
    info['collection'] = any(t['image'] for t in tiles.values())
    return info


def image(path):
    if path not in _cache:
        _cache[path] = Image.open(path).convert('RGBA')
    return _cache[path]


def source_rect(ts, tid, tw, th):
    """The tile's cell within its sheet, honouring margin and spacing."""
    if ts['collection']:
        return None
    m, sp = ts.get('margin') or 0, ts.get('spacing') or 0
    cols = ts.get('columns') or 1
    return (m + (tid % cols) * (tw + sp),
            m + (tid // cols) * (th + sp))


def tile_image(ts, tid, tw, th):
    """(image, sx, sy) for one tile of a tileset, or None if it has no art."""
    if ts['collection']:
        got = ts['tiles'].get(tid)
        if not got or not got['image']:
            return None
        return image(got['image']), 0, 0
    if not ts['image']:
        return None
    sx, sy = source_rect(ts, tid, tw, th)
    return image(ts['image']), sx, sy


def load_sets(map_path, tw):
    """[(tileset, firstgid, tw, th)] in map order, split by geometry."""
    m = json.load(open(map_path))
    tsx_dir = os.path.dirname(map_path)
    sets = []
    for ref in m['tilesets']:
        if 'source' in ref:
            ts = parse_tsx(os.path.join(tsx_dir, ref['source']))
        else:
            ts = dict(ref)
            ts['tiles'] = {}
            ts['collection'] = False
            ts['image'] = rooted(tsx_dir, ref.get('image', '')) or None
        sets.append((ts, ref['firstgid'],
                     ts.get('tilewidth') or tw, ts.get('tileheight') or tw))
    return m, sets


def which_set(sets, gid, tw):
    """The tileset a gid falls into (a terrain set of the map's cell size),
    or None when the gid belongs to a 16x16 art set or nothing."""
    for ts, first, sw, sh in sets:
        if sw != tw or sh != tw:
            continue                      # art set: not painted as terrain
        if gid >= first and gid < first + (ts.get('tilecount') or 1 << 30):
            return ts, first
    return None


COLOURS = {'Spawn': (0, 228, 54), 'Room': (60, 60, 90), 'Exit': (255, 0, 77),
           'Key': (255, 236, 39), 'Lock': (255, 163, 0), 'Door': (255, 119, 168),
           'Switch': (255, 0, 77), 'Spring': (0, 228, 54), 'Archer': (255, 0, 77),
           'Melee': (255, 0, 77), 'Laser': (255, 0, 77), 'Rocketeer': (255, 0, 77),
           'Bomber': (255, 0, 77), 'Checkpoint': (0, 228, 54),
           'Winch': (41, 173, 255), 'Pusher': (255, 0, 77)}


def render(map_path, out_path, scale=2, terrain_only=False):
    m, sets = load_sets(map_path, 8)
    W, H = m['width'], m['height']
    TW, TH = m['tilewidth'], m['tileheight']
    out = Image.new('RGBA', (W * TW, H * TH), (135, 206, 235, 255))  # sky blue

    # the terrain grid: every visible 8x8 tile layer, each cell cut from
    # whichever tileset its gid belongs to
    for layer in m['layers']:
        if layer['type'] != 'tilelayer' or not layer.get('visible', True):
            continue
        if (layer.get('name') or '').lower() == 'background':
            continue
        for i, gid in enumerate(layer['data']):
            if not gid:
                continue
            found = which_set(sets, gid, TW)
            if not found:
                continue
            ts, first = found
            art = tile_image(ts, gid - first, ts['tilewidth'], ts['tileheight'])
            if not art:
                continue
            img, sx, sy = art
            cell = img.crop((sx, sy, sx + TW, sy + TH))
            x, y = i % W, i // W
            out.alpha_composite(cell, (x * TW, y * TH))

    d = None if terrain_only else ImageDraw.Draw(out)
    if d is not None:
        for layer in m['layers']:
            if layer['type'] != 'objectgroup' or not layer.get('visible', True):
                continue
            for o in layer.get('objects', []):
                props = {p['name']: p.get('value') for p in o.get('properties', [])}
                gid = o.get('gid')
                kind = props.get('kind')
                if not kind and gid:
                    for ts, first, sw, sh in sets:
                        if gid >= first and gid < first + (ts.get('tilecount') or 1 << 30):
                            kind = (ts['tiles'].get(gid - first, {}) or {}).get(
                                'props', {}).get('kind')
                            break
                kind = kind or o.get('type') or o.get('class') or '?'
                x, y = o.get('x', 0), o.get('y', 0)
                if gid:
                    # a placed tile: art is the 16x16 cell, anchored at its
                    # bottom edge in Tiled
                    got = None
                    for ts, first, sw, sh in sets:
                        if gid >= first and gid < first + (ts.get('tilecount') or 1 << 30):
                            got = tile_image(ts, gid - first, sw, sh)
                            break
                    if got:
                        img, sx, sy = got
                        d.rectangle([x, y - sh, x + sw - 1, y - 1],
                                    outline=(0, 0, 0, 255))
                        out.alpha_composite(img.crop((sx, sy, sx + sw, sy + sh)),
                                            (int(x), int(y - sh)))
                    continue
                w = o.get('width', 0) or (ART if o.get('point') is None else 0)
                h = o.get('height', 0) or (ART if o.get('point') is None else 0)
                if o.get('point'):
                    w, h = ART, ART
                    y -= ART      # point objects: feet at the point
                col = COLOURS.get(kind, (255, 0, 255))
                d.rectangle([x, y, x + w - 1, y + h - 1], outline=col + (255,))
                d.text((x + 1, y + 1), (o.get('name') or kind)[:6], fill=col + (255,))

    if scale != 1:
        out = out.resize((W * TW * scale, H * TH * scale), Image.NEAREST)
    out.save(out_path)
    print(f"{map_path} -> {out_path} ({W*TW*scale}x{H*TH*scale})")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    args = [a for a in sys.argv[1:] if a != '--terrain-only']
    render(args[0], args[1], int(args[2]) if len(args) > 2 else 2,
           terrain_only='--terrain-only' in sys.argv)
