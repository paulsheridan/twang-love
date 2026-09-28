#!/usr/bin/env python3
"""Migrates twang Tiled maps from 16px tiles to 8px tiles.

Run after tools/build_tsx_8px.py (the terrain tileset is rebuilt in
place at 8x8, columns 32, tilecount 1024; the old 16px cell O becomes
sub-tiles at Tiled's linear ids (O//16)*64 + (O%16)*2 + {0,1,32,33}
= TL, TR, BL, BR over the untouched spritesheet).

Per map:
  * tilewidth/height 16 -> 8; width/height x2 (same world in px)
  * slope wedge cells are pre-filled like-for-like (/\\floor and plain
    ceils -> solid 5; sticky ceils -> sticky solid 56), so slope tiles
    never reach the 8px grid
  * every cell expands into its four sub-tiles (kind-marker cells too:
    their art is a full 16px cell; the spawn scan dedupes the four
    sub-cells back to one spawn point per art cell)
  * objects: entity anchors are re-derived in the old loader's frame
    (snap to 16, then double), so the 8px loader lands them exactly
    where the 16px engine did; rooms double as plain rectangles;
    mover/pusher `distance`/`side` (tile-count units) double to keep
    their px reach
  * object gids remap: art 96-103 / 128-170 -> the chars16 sprite
    tileset (gid = 1025 + (art - 96), tileset ref added on demand);
    everything else -> the terrain tileset's top-left sub (TL gid)
  * .tx templates get the same gid remap and point at chars16.tsx

usage:
    python3 tools/migrate_maps_8px.py maps/level1.json [more ...]
    python3 tools/migrate_maps_8px.py   # all maps + rooms fixture + templates
"""
import json
import glob
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

CHARS_FIRSTGID = 1025
CHARS_BASE = 96
# cells reserved for chars16.tsx; 135 (phase platform) stays terrain
RESERVED = (set(range(96, 104)) | set(range(128, 171))) - {135}
# like-for-like slope fills (see tools/fill_slopes_16px.py)
SLOPE_FLOOR = {6, 7, 13, 14, 61, 62}
SLOPE_STICKY = {54, 55}
FILL_FLOOR, FILL_STICKY = 5, 56
KINDS = {"spawn", "key", "lock", "door", "switch", "spring", "winch",
         "exit", "checkpoint", "archer", "melee", "laser", "rocketeer",
         "bomber", "gun", "pusher", "updraft", "outdraft", "mover",
         "mover_trigger", "movertrigger"}


def sub_gid(art):
    """GID of art cell O's top-left 8px sub-tile (Tiled's linear id + 1)."""
    return (art // 16) * 64 + (art % 16) * 2 + 1


def round16(v):
    return math.floor(v / 16 + 0.5) * 16


def object_kind(o):
    props = o.get("properties")
    if isinstance(props, list):
        for p in props:
            if p.get("name") == "kind":
                return p.get("value")
    elif isinstance(props, dict):
        return props.get("kind")
    t = (o.get("type") or o.get("class") or "").lower()
    return t if t in KINDS else None


def expand_layer(data, old_w, old_h, path):
    """old row-major gids -> new (2W)x(2H) gids, row-major. Each old row
    expands into two new rows: TL/TR fill the even row, BL/BR the odd."""
    out = []
    for r in range(old_h):
        top, bottom = [], []
        for c in range(old_w):
            g = data[r * old_w + c] or 0
            art = g - 1
            if art == 0:
                tl = tr = bl = br = 0
            else:
                if art in SLOPE_FLOOR:
                    art = FILL_FLOOR
                elif art in SLOPE_STICKY:
                    art = FILL_STICKY
                if art in RESERVED:
                    sys.exit("%s: reserved sprite art %d used in a tile "
                             "layer" % (path, art))
                base = sub_gid(art)          # TL gid
                tl, tr = base, base + 1
                bl, br = base + 32, base + 33
            top.extend((tl, tr))
            bottom.extend((bl, br))
        out.extend(top)
        out.extend(bottom)
    return out


def migrate_object(o, chars_needed):
    """Positions are PRESERVED in px (the world's pixel size is unchanged;
    only the tile grid doubles). Each entity's old final position was
    snapped to the 16px grid at scan time, so store the snapped anchor
    (round16 of the old raw anchor) plus the loader's own anchor offset:
    the new 8px loader then reproduces the same px exactly."""
    if not o.get("gid"):
        cls = (o.get("type") or o.get("class") or "").lower()
        if cls == "room" or object_kind(o) == "room":
            for k in ("x", "y", "width", "height"):
                if k in o:
                    o[k] = round16(o[k])
            return
    kind = object_kind(o)
    gid = o.get("gid")
    if gid:
        # old loader anchor math (dims stay 16px art units)
        w = o.get("width") or 16
        h = o.get("height") or 16
        rot = math.floor(((o.get("rotation") or 0) % 360) / 90 + 0.5) * 90
        if rot:
            rad = math.radians(rot)
            cs, sn = math.cos(rad), math.sin(rad)
            minx = miny = math.inf
            for px, py in ((0, 0), (w, 0), (w, -h), (0, -h)):
                rx, ry = px*cs - py*sn, px*sn + py*cs
                minx, miny = min(minx, rx), min(miny, ry)
            wx, wy = o["x"] + minx, o["y"] + miny
        else:
            wx, wy = o["x"], o["y"] - h
        relx, rely = wx - o["x"], wy - o["y"]
        if kind == "spawn":
            pass  # spawn points keep their raw px position
        else:
            o["x"] = round16(wx) - relx
            o["y"] = round16(wy) - rely
        art = gid - 1
        if art in RESERVED:
            o["gid"] = CHARS_FIRSTGID + (art - CHARS_BASE)
            chars_needed[0] = True
        else:
            o["gid"] = sub_gid(art)
        # width/height stay 16 (art units): the loader anchors tile
        # objects at their 16px art box, identical to the 16px pipeline
    elif o.get("width") is None and o.get("height") is None:
        pass  # point objects: feet at the raw px point (unchanged)
    else:
        # plain rect entity (movers etc): dims stay in art units (the
        # footprint derives from them against the 16px art tile)
        o["x"] = round16(o["x"])
        o["y"] = round16(o["y"])
    # tile-count properties keep their px reach (a tile is now 8px)
    props = o.get("properties")
    if isinstance(props, list):
        for p in props:
            if p.get("name") in ("distance", "side") and isinstance(
                    p.get("value"), (int, float)):
                p["value"] = p["value"] * 2


def migrate(path):
    with open(path) as f:
        m = json.load(f)
    assert m.get("type") == "map", path
    if m["tilewidth"] != 16 or m["tileheight"] != 16:
        print("%s: skipped (already %dx%d tiles)"
              % (path, m["tilewidth"], m["tileheight"]))
        return

    chars_needed = [False]
    old_w, old_h = m["width"], m["height"]
    m["tilewidth"] = m["tileheight"] = 8
    m["width"], m["height"] = old_w * 2, old_h * 2
    for layer in m.get("layers", []):
        if layer.get("type") == "tilelayer":
            if layer.get("width"):
                layer["width"], layer["height"] = layer["width"] * 2, layer["height"] * 2
            if layer.get("data"):
                layer["data"] = expand_layer(layer["data"], old_w, old_h, path)
        elif layer.get("type") == "objectgroup":
            for o in layer.get("objects", []):
                migrate_object(o, chars_needed)

    # tilesets: keep the terrain ref; add chars16 when sprite art is used
    ts = m.get("tilesets") or []
    assert ts and ts[0].get("source"), "%s has no external tileset" % path
    assert "twang.tsx" in ts[0]["source"], path
    if chars_needed[0]:
        src = ts[0]["source"].replace("twang.tsx", "chars16.tsx")
        if not any("chars16.tsx" in t.get("source", "") for t in ts):
            ts.append({"firstgid": CHARS_FIRSTGID, "source": src})

    with open(path, "w") as f:
        json.dump(m, f, separators=(",", ":"), ensure_ascii=False)
    print("%s: migrated to 8px (%dx%d tiles)%s"
          % (path, m["width"], m["height"],
             " + chars16 tileset" if chars_needed[0] else ""))


def migrate_template(path):
    with open(path) as f:
        xml = f.read()
    def remap(match):
        art = int(match.group(1)) - 1
        gid = (CHARS_FIRSTGID + (art - CHARS_BASE)
               if art in RESERVED else sub_gid(art))
        return 'gid="%d"' % gid
    xml = re.sub(r'gid="(\d+)"', remap, xml)
    xml = xml.replace('source="twang.tsx"', 'source="chars16.tsx"')
    xml = xml.replace('firstgid="1"', 'firstgid="%d"' % CHARS_FIRSTGID)
    with open(path, "w") as f:
        f.write(xml)
    print("%s: template remapped" % path)


def main():
    args = sys.argv[1:]
    if not args:
        args = sorted(glob.glob(os.path.join(ROOT, "maps", "*.json")))
        args += sorted(glob.glob(os.path.join(ROOT, "maps", "*.tx")))
        args.append(os.path.join(ROOT, "tests", "rooms_fixture.json"))
    for p in args:
        if p.endswith(".tx"):
            migrate_template(p)
        else:
            migrate(p)


if __name__ == "__main__":
    main()
