#!/usr/bin/env python3
"""One-shot migration: extend maps/farmhouse.json with a second room.

Adds 60 tile columns (960x640 px, one "field" room) to the right of the
farmhouse, continues the terrain/backdrop into it, and adds the object
layer the map was missing: two "Room" rectangles (the intro farmhouse
room and the field) plus a spawn point inside the building.

Re-running is safe-ish but pointless: it assumes the pre-extension map.
Run from the project root:  python3 tools/extend_farmhouse.py
"""

import json

MAP = "maps/farmhouse.json"
NEW_COLS = 60          # the field room's width in tiles (960px, 640 tall)
GROUND_TILE = 4        # gid of solid tile id 3
BACKGROUND_TILE = 29   # gid of backdrop tile id 28

with open(MAP, "rb") as f:
    m = json.load(f)

W, H = m["width"], m["height"]
NEW_W = W + NEW_COLS
assert m["infinite"] is False

def tile_index(r, c, width):
    return r * width + c

for layer in m["layers"]:
    if layer["type"] == "tilelayer":
        data = layer["data"]
        assert layer["width"] == W and layer["height"] == H
        grown = [0] * (NEW_W * H)
        for r in range(H):
            for c in range(W):
                grown[r * NEW_W + c] = data[r * W + c]
        if layer["name"] == "Background":
            # the backdrop walls carry into the new room
            for r in range(H):
                for c in range(W, NEW_W):
                    grown[r * NEW_W + c] = BACKGROUND_TILE
        elif layer["name"] == "Ground":
            # the field floor continues the seam's surface height
            # (the mound at the old right edge tops out at row 13)
            for r in range(13, H):
                for c in range(W, NEW_W):
                    grown[r * NEW_W + c] = GROUND_TILE
        layer["data"] = grown
        layer["width"] = NEW_W

rooms = [
    {"name": "farmhouse", "type": "Room", "class": "Room",
     "x": 0, "y": 0, "width": W * 16, "height": H * 16,
     "rotation": 0, "visible": True},
    {"name": "field", "type": "Room", "class": "Room",
     "x": W * 16, "y": 0, "width": NEW_COLS * 16, "height": H * 16,
     "rotation": 0, "visible": True},
]
spawn = {"name": "spawn", "type": "Spawn", "class": "Spawn", "point": True,
         "x": 96, "y": 492, "rotation": 0, "visible": True}

m["layers"].append({
    "type": "objectgroup", "name": "Rooms", "visible": True,
    "draworder": "topdown",
    "objects": [spawn] + rooms,
})
m["width"] = NEW_W
if "nextlayerid" in m:
    m["nextlayerid"] = max(m.get("nextlayerid", 1),
                           max(l.get("id", 0) for l in m["layers"]) + 1)
if "nextobjectid" in m:
    m["nextobjectid"] = max(m.get("nextobjectid", 1),
                            len(m["layers"]) + 10)

with open(MAP, "w", newline="\n") as f:
    json.dump(m, f, indent=1)
print("extended %s: %d -> %d columns, rooms farmhouse + field" %
      (MAP, W, NEW_W))
