-- Report what the game actually does with every tile in a level, straight
-- from the real loader (src/tiled.lua) and the real world queries
-- (src/world.lua) -- so "I marked it solid" and "the player stops at it"
-- are checked against the same code the game runs, not against the .tsx
-- file's own idea of itself.
--
-- Usage (from the project root):
--   luajit tools/check_tiles.lua                        -- every tile
--   luajit tools/check_tiles.lua maps/roomgrid.json     -- a specific level
--   luajit tools/check_tiles.lua maps/roomgrid.json 2 3 4 5 13
--                                                          -- specific tile ids
--
-- Every tile is reported twice over, which is the whole point:
--   * what the TILESET declares -- read straight out of the .tsx, so
--     unplaced tiles are covered too (the game only resolves the gids a
--     map actually paints, so asking the loader alone cannot tell you
--     whether an unused tile is flagged)
--   * what the GAME does with it -- the loader's own record plus the
--     world's own solid_for_arrow / sticky_at answers, for placed tiles
--
-- Not part of the game: an authoring/QA tool.

local tiled  = dofile("src/tiled.lua")
local config = dofile("src/config.lua")
local World  = dofile("src/world.lua")
local json   = dofile("lib/json.lua")

local map  = arg[1] or config.map_file
local want = {}
for i = 2, #arg do want[tonumber(arg[i])] = true end

-- The gameplay flags a terrain tile may declare (src/tiled.lua). "kind" is
-- an entity role, not a terrain flag, so it is not listed here.
local FLAGS = { "solid", "bounce", "friction", "arrow_pass",
                "runnable", "oneway", "phase" }

local TW = config.tile_size
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ==== the tilesets, read directly so unplaced tiles are included ====
-- Mirrors parse_tsx's property regex; the point is to see the file as it is
-- on disk, independently of anything the game chose to resolve.
local function tsx_props(path)
  local xml = read_file(path)
  if not xml then return nil end
  xml = xml:gsub('<tile%s+id="(%d+)"[^>]*/>', '<tile id="%1"></tile>')
  local out = {}
  for id, body in xml:gmatch('<tile%s+id="(%d+)"%s*(.-)</tile>') do
    local props = {}
    for pm in body:gmatch("<property%s+(.-)/>") do
      local name, typ, val
      name = pm:match('name="([^"]*)"')
      typ  = pm:match('type="([^"]*)"')
      val  = pm:match('value="([^"]*)"')
      if name then
        if typ == "bool" then
          props[name] = (val == "true")
        elseif typ == "int" or typ == "float" then
          props[name] = tonumber(val)
        else
          props[name] = val
        end
      end
    end
    out[tonumber(id)] = props
  end
  return out
end

-- ==== the level, through the real loader ====
local level = tiled.load(map)
local world = World.new(level, {
  doors = {}, springs = {}, switches = {}, pushers = {}, movers = {},
}, TW)

-- how many cells use each gid, and one cell where it is placed
local placed, first_at = {}, {}
for r = 0, level.MAP_H - 1 do
  local row = level.map[r + 1]
  for c = 0, level.MAP_W - 1 do
    local key = tonumber(row:sub(c*4 + 1, c*4 + 4), 16)
    if key ~= 0 then
      placed[key] = (placed[key] or 0) + 1
      if not first_at[key] then first_at[key] = { c = c, r = r } end
    end
  end
end

print("level: " .. map)
print(string.rep("=", 100))

-- ---- every tile id in every referenced tileset ----
local map_json = json.decode(read_file(map))
local dir = map:match("^(.-)[^/\\]*$") or ""
local by_id, sources = {}, {}
for _, ref in ipairs(map_json.tilesets or {}) do
  local props, label
  if ref.source then
    props = tsx_props(dir .. ref.source)
    label = ref.source
  else
    props = {}
    for _, t in ipairs(ref.tiles or {}) do props[t.id] = t.properties or {} end
    label = "embedded tileset (firstgid " .. tostring(ref.firstgid) .. ")"
  end
  local firstgid = ref.firstgid
  for id, p in pairs(props or {}) do
    by_id[id] = p
    sources[id] = label .. " (gid " .. tostring(firstgid + id) .. ")"
  end
end

local ids = {}
for id in pairs(by_id) do ids[#ids + 1] = id end
table.sort(ids)

print(string.format("%-4s %-9s %-8s %-26s %s",
  "id", "gid", "cells", "declared in the tileset", "what the game does"))
print(string.rep("-", 100))

local walk_through, solid_count, no_props = 0, 0, 0

for _, id in ipairs(ids) do
  if not next(want) or want[id] then
    local p = by_id[id]
    local list = {}
    for _, f in ipairs(FLAGS) do
      if p[f] then list[#list + 1] = f end
    end
    if #list == 0 then no_props = no_props + 1 end

    -- find the gid the loader would give this tile, and how the world
    -- actually answers for a cell painted with it
    local gid, behaviour = nil, "(not placed in this level)"
    for g, rec in pairs(level.tiles_by_key) do
      if rec.id == id then gid = g break end
    end
    if gid and placed[gid] then
      local at = first_at[gid]
      local px, py = at.c * TW + TW/2, at.r * TW + TW/2
      local bodies = world:solid_at(px, py)
      local arrows = world:solid_for_arrow(px, py)
      local bounces = world:sticky_at(px, py)
      local passes = level.tiles_by_key[gid].arrow_pass or false
      if passes then
        behaviour = "arrows pass through, bodies still blocked"
      elseif bodies and bounces then
        behaviour = "SOLID + BOUNCE: bodies stop, arrows reflect"
      elseif bodies then
        behaviour = "SOLID: bodies stop, arrows stick"
      elseif bounces then
        behaviour = "BOUNCE only: bodies walk through, arrows reflect"
      else
        behaviour = "PAINT ONLY: everything passes through"
      end
      if bodies then solid_count = solid_count + 1 end
      if not bodies and not bounces then walk_through = walk_through + 1 end
    end

    print(string.format("%-4d %-9s %-8d %-26s %s", id,
      tostring(gid or "?"), placed[gid] or 0,
      #list > 0 and table.concat(list, ",") or "(none)", behaviour))
  end
end

print(string.rep("-", 100))
print(string.format("tiles: %d in the tileset   placed in this level: %d   "
  .. "solid: %d   walk-through: %d   with no properties at all: %d",
  #ids, (function() local n = 0 for _ in pairs(placed) do n = n + 1 end return n end)(),
  solid_count, walk_through, no_props))

-- ---- the traps, said plainly ----
local any_flag = 0
for _, id in ipairs(ids) do
  for _, f in ipairs(FLAGS) do
    if by_id[id][f] then any_flag = any_flag + 1 break end
  end
end

if any_flag == 0 then
  print()
  print("NOTHING IS FLAGGED. No tile in this level's tileset declares a single")
  print("gameplay property, so no tile is solid and the player passes")
  print("through all of them. If you flagged tiles in Tiled, the TILESET was")
  print("not saved -- an external .tsx is a separate file from the map, and")
  print("saving the map does not save it. Save the .tsx too.")
elseif solid_count == 0 then
  print()
  print("No placed tile stops a body. Properties are being read, but the")
  print("tiles you painted are not among the solid ones.")
end
