-- tools/p8_to_tiled.lua: one-shot migration of the twang pico-8 cart into
-- a Tiled-editable JSON map. The cart is the source of truth for this run;
-- afterwards the map is edited in Tiled and consumed directly by the game.
--
-- Entities (key/lock/door/archer/melee) are emitted as tile OBJECTS on
-- "items"/"entities" object layers (the game's only entity source); the
-- spawn marker stays a ground tile. Entities come out ungrouped -- name
-- them "<kind>_<group>" in Tiled (e.g. key_01 / lock_01 / door_01) to
-- pair puzzles.
--
-- usage: luajit tools/p8_to_tiled.lua <cart.p8> <out.json>
--   e.g. luajit tools/p8_to_tiled.lua ../twang.p8 maps/level1.json

local here = (arg and arg[0]:match("^(.*[/\\])")) or "./"
package.path = here .. "../?.lua;" .. package.path

local json  = require("lib.json")
local tiled = require("src.tiled")

local p8path, outpath = arg[1], arg[2]
assert(p8path and outpath,
  "usage: luajit tools/p8_to_tiled.lua <cart.p8> <out.json>")

-- ===== read the cart =====
local f = io.open(p8path, "rb")
assert(f, "cannot open " .. p8path)
local content = f:read("*a")
f:close()

local function split_lines(s)
  local t, i = {}, 1
  while i <= #s do
    local j = s:find("[\r\n]", i)
    if not j then t[#t + 1] = s:sub(i) break end
    t[#t + 1] = s:sub(i, j - 1)
    i = j + 1
    if s:byte(j) == 13 and s:byte(i) == 10 then i = j + 2 end
  end
  return t
end

local map_rows, gff_hex = {}, nil
local section = nil
for _, l in ipairs(split_lines(content)) do
  if l:match("^__%a+__$") then
    section = l
  elseif section == "__map__" and #l >= 2 then
    map_rows[#map_rows + 1] = l
  elseif section == "__gff__" and not gff_hex and #l >= 2 then
    gff_hex = l
  end
end

assert(#map_rows > 0, "no __map__ section found in " .. p8path)
assert(gff_hex, "no __gff__ section found in " .. p8path)

local W = #map_rows[1] / 2
local H = #map_rows
assert(W % 1 == 0 and W <= 256, "bad map width: " .. tostring(#map_rows[1]))

-- per-tile flag bytes (bit0 solid, bit1 sticky, bit2 friction)
local flags = {}
for t = 0, 255 do
  flags[t + 1] = tonumber(gff_hex:sub(t * 2 + 1, t * 2 + 2), 16) or 0
end

-- ===== build the Tiled map =====
-- layer data: GIDs are 1-based (firstgid 1), so GID = tile + 1
local KINDS  = {}
for name, id in pairs(tiled.DEFAULT_KINDS)  do KINDS[id]  = name end
local SLOPES = {}
for id, s   in pairs(tiled.DEFAULT_SLOPES) do SLOPES[id] = s end

local data, ents = {}, {}
for r = 0, H - 1 do
  local row = map_rows[r + 1]
  assert(#row == W * 2, "ragged map row " .. r)
  for c = 0, W - 1 do
    local t = tonumber(row:sub(c * 2 + 1, c * 2 + 2), 16) or 0
    local kind = KINDS[t]
    if kind and kind ~= "spawn" then
      -- entity tiles become objects (bottom-anchored like Tiled tile
      -- objects); ungrouped until named in Tiled. Cart switches drive
      -- every system (any strike flipped the cart's phase tiles), so
      -- they convert with the "phase" flag on
      local ent = {
        gid = t + 1, name = "", x = c * 16, y = r * 16 + 16,
        width = 16, height = 16,
      }
      if kind == "switch" then
        ent.properties = { { name = "phase", type = "bool", value = true } }
      end
      ents[#ents + 1] = ent
      t = 0
    end
    data[#data + 1] = t + 1
  end
end

-- tileset entries: pico-8 flags -> custom properties, plus kind/slope
local tiles = {}
for t = 0, 127 do
  local fl = flags[t + 1]
  local props = {}
  if math.floor(fl / 1) % 2 == 1 then
    props[#props + 1] = { name = "solid",    type = "bool",   value = true }
  end
  if math.floor(fl / 2) % 2 == 1 then
    props[#props + 1] = { name = "sticky",   type = "bool",   value = true }
  end
  if math.floor(fl / 4) % 2 == 1 then
    props[#props + 1] = { name = "friction", type = "bool",   value = true }
  end
  if KINDS[t] then
    props[#props + 1] = { name = "kind",  type = "string", value = KINDS[t] }
  end
  if SLOPES[t] then
    props[#props + 1] = { name = "slope", type = "string", value = SLOPES[t] }
  end
  if #props > 0 then
    tiles[#tiles + 1] = { id = t, properties = props }
  end
end

-- object layers: puzzle items on "items", enemies on "entities"
local items, entities = {}, {}
for _, e in ipairs(ents) do
  local kind = KINDS[e.gid - 1]
  if kind == "key" or kind == "lock" or kind == "door" then
    items[#items + 1] = e
  else
    entities[#entities + 1] = e
  end
end

local map = {
  type = "map",
  version = "1.10",
  tiledversion = "1.10.2",
  orientation = "orthogonal",
  renderorder = "right-down",
  width = W,
  height = H,
  tilewidth = 16,
  tileheight = 16,
  infinite = false,
  compressionlevel = -1,
  nextlayerid = 3,
  nextobjectid = 1,
  layers = {
    {
      type = "tilelayer",
      name = "ground",
      id = 1,
      x = 0,
      y = 0,
      width = W,
      height = H,
      opacity = 1,
      visible = true,
      data = data,
    },
    {
      type = "objectgroup",
      name = "entities",
      id = 2,
      x = 0,
      y = 0,
      objects = entities,
    },
    {
      type = "objectgroup",
      name = "items",
      id = 3,
      x = 0,
      y = 0,
      objects = items,
    },
  },
  tilesets = {
    {
      type = "tileset",
      name = "twang",
      firstgid = 1,
      image = "../spritesheet.png",
      imagewidth = 256,
      imageheight = 256,
      margin = 0,
      spacing = 0,
      columns = 16,
      tilecount = 256,
      tilewidth = 16,
      tileheight = 16,
      tiles = tiles,
    },
  },
}

local out = io.open(outpath, "wb")
assert(out, "cannot write " .. outpath)
out:write(json.encode(map))
out:close()

-- ===== summary =====
local kind_counts = {}
for _, e in ipairs(ents) do
  local k = KINDS[e.gid - 1]
  kind_counts[k] = (kind_counts[k] or 0) + 1
end
local n_flagged = 0
for t = 0, 127 do
  if flags[t + 1] ~= 0 then n_flagged = n_flagged + 1 end
end

print(string.format("wrote %s: %dx%d tiles, %d tileset entries with properties",
  outpath, W, H, #tiles))
print(string.format("  entities as objects: %d items, %d enemies",
  #items, #entities))
for _, name in ipairs({"spawn", "key", "lock", "door", "archer", "melee"}) do
  print(string.format("  %-7s x%d", name, kind_counts[name] or 0))
end
print(string.format("  %d tiles carry solid/sticky/friction flags", n_flagged))
print("keys/locks/doors are ungrouped; name them <kind>_<group> in Tiled")
print("(e.g. key_01 / lock_01 / door_01) to pair up puzzles")
