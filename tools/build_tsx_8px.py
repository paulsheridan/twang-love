#!/usr/bin/env python3
"""Rebuilds maps/legacy/twang.tsx as the 8px terrain tileset.

The spritesheet stays byte-identical (256x256); the tileset merely
re-indexes it as 32 columns of 8x8 cells (1024 tiles). Old 16px cell O
(row-major over 16 columns) maps to the four sub-tiles at Tiled's own
linear 8px ids: TL = (O//16)*64 + (O%16)*2, TR = TL+1, BL = TL+32,
BR = TL+33 (row-major over 32 columns; the quadrant order is
TL, TR, BL, BR).

Per-tile property rules, from the 16px tileset's records:

  * solid / sticky / friction / arrow_pass / runnable / oneway / phase
    -> cloned to all four sub-tiles (terrain material subdivides)
  * kind (object markers: spawn, key, lock, door, switch, exit)
    -> kept on the top-left sub only (markers never subdivide; map
    scans match floor(tile/4) == label)
  * kind on moved sprite art (137 archer, 138 laser, 140 melee,
    143 bomber) is NOT emitted here: cells 96-103 and 128-170 are
    reserved for maps/legacy/chars16.tsx (the 16px sprite tileset) and the
    loader rejects their use in terrain layers
  * slope records are dropped: slope collision is removed from the game
  * tile 32 keeps ONLY its spring_ext record (no solid): the 16px
    tileset defined it twice and the loader's last-record-wins parsing
    resolved it non-solid; the 8px tileset preserves that behaviour

Run once, before tools/migrate_maps_8px.py.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TSX = os.path.join(HERE, "..", "maps", "legacy", "twang.tsx")

FLAGS = ("solid", "sticky", "friction", "arrow_pass", "runnable",
         "oneway", "phase")
# reserved sprite art (chars16.tsx territory); cell 135 stays terrain
# (the phase platform, used as real collision in level1 + springside)
MOVED = (set(range(96, 104)) | set(range(128, 171))) - {135}

HEADER = """\
<?xml version="1.0" encoding="UTF-8"?>
<!-- twang terrain tileset: 8x8 cells over the untouched spritesheet
     (256x256 = 32 columns x 32 rows, 1024 tiles, firstgid 1 in maps).
     Old 16px cell O maps to sub-tiles at linear ids
     (O//16)*64 + (O%16)*2 + {0, 1, 32, 33} (TL, TR, BL, BR).

     Reserved sprite art (NOT terrain; property records live in
     chars16.tsx): cells 96-103 and 128-170. Cell 135 stays terrain
     (the phase platform; solid + phase on all four subs). Tile-layer
     use of reserved cells is rejected by the loader. Slope tiles and
     the slope property are gone: slope collision was removed. -->
"""


def sub_ids(art):
    """Linear 8px tile ids of art cell O's quadrants (TL, TR, BL, BR)."""
    base = (art // 16) * 64 + (art % 16) * 2
    return base, base + 1, base + 32, base + 33


def parse_props(xml):
    """art label -> {prop: (type, value)} from the 16px tsx."""
    props = {}
    xml = re.sub(r'<tile\s+id="(\d+)"[^>]*/>',
                 lambda m: '<tile id="%s"></tile>' % m.group(1), xml)
    for m in re.finditer(r'<tile\s+id="(\d+)"\s*(.*?)</tile>', xml, re.S):
        art = int(m.group(1))
        body = m.group(2)
        d = props.setdefault(art, {})
        for pm in re.finditer(r'<property\s+(.*?)/>', body, re.S):
            attrs = dict(re.findall(r'([\w_]+)\s*=\s*"([^"]*)"', pm.group(1)))
            if attrs.get("name"):
                d[attrs["name"]] = (attrs.get("type", "string"),
                                    attrs.get("value", ""))
    return props


def prop_xml(name, ptype, value):
    if ptype in ("bool", "int", "float"):
        return ('   <property name="%s" type="%s" value="%s"/>\n'
                % (name, ptype, value))
    return '   <property name="%s" value="%s"/>\n' % (name, value)


def main():
    with open(TSX) as f:
        old = f.read()
    m = re.search(r'tilewidth="(\d+)"', old)
    if m and int(m.group(1)) != 16:
        sys.exit("twang.tsx is not the 16px tileset (refusing to run twice)")
    props = parse_props(old)

    out = [HEADER,
           '<tileset version="1.10" tiledversion="1.11.0" name="twang"'
           ' tilewidth="8" tileheight="8" tilecount="1024" columns="32">\n',
           ' <image source="../spritesheet.png" width="256" height="256"/>\n']

    for art in sorted(props):
        p = props[art]
        if art in MOVED:
            # reserved sprite art: no terrain records at all
            continue
        if "slope" in p:
            continue  # slopes removed
        if art == 32 and "spring_ext" in p:
            # preserve the loader's last-record-wins quirk: the 16px
            # tileset defined tile 32 twice (solid, then spring_ext) and
            # the loader resolved it to spring_ext only (non-solid)
            rec = ' <tile id="%d">\n  <properties>\n%s  </properties>\n </tile>\n'
            out.append(rec % (sub_ids(32)[0],
                              prop_xml("spring_ext", p["spring_ext"][0],
                                       p["spring_ext"][1])))
            continue
        kind = p.get("kind")
        tl, tr, bl, br = sub_ids(art)
        tids = (tl, tr, bl, br)
        for sub in range(4):
            tid = tids[sub]
            lines = []
            for flag in FLAGS:
                if flag in p:
                    lines.append(prop_xml(flag, p[flag][0], p[flag][1]))
            if kind and sub == 0:
                lines.append(prop_xml("kind", p["kind"][0], p["kind"][1]))
            if not lines:
                continue
            rec = ' <tile id="%d">\n  <properties>\n%s  </properties>\n </tile>\n'
            out.append(rec % (tid, "".join(lines)))

    out.append("</tileset>\n")
    with open(TSX, "w") as f:
        f.write("".join(out))
    print("rewrote %s as the 8px tileset (%d records)"
          % (os.path.normpath(TSX), sum(1 for l in out if l.startswith(" <tile"))))


if __name__ == "__main__":
    main()
