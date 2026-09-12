-- Level assembly: turns a src/tiled.lua load result into the game's live
-- entity lists (spawns, enemies, arrows, particles) and the puzzle
-- interactables (keys/locks/doors/switches/springs).
--
-- Entities are Tiled objects (see src/tiled.lua): roles from the object's
-- kind/class, puzzle groups from names, extra custom properties override
-- entity defaults (per-instance tuning like shoot cooldowns).

local Util = require("src.util")

local Level = {}

-- Snaps an object's pixel position to the tile grid.
local function snap_tile(v, tw)
  return math.floor(v / tw + 0.5) * tw
end

-- Applies an object's extra custom properties onto an entity; custom
-- values override entity defaults.
local function apply_object_props(e, o)
  for k, v in pairs(o) do
    if k ~= "kind" and k ~= "x" and k ~= "y" and k ~= "g"
    and k ~= "name" and k ~= "type" then e[k] = v end
  end
end

--- Scans a Tiled level into live entity lists and resolves the special
--- tile ids (level tileset overrides, pico-8 cart fallbacks).
--- Returns ents, tiles.
function Level.build(level, config)
  local tw = config.tile_size
  local cfg = config.enemies

  -- tile ids: the level tileset's kinds win over the cart fallbacks
  local tiles = {
    key        = level.special.key        or config.tiles.key,
    lock       = level.special.lock       or config.tiles.lock,
    door       = level.special.door       or config.tiles.door,
    switch     = level.special.switch     or config.tiles.switch,
    spring     = level.special.spring     or config.tiles.spring,
    spring_ext = level.special.spring_ext or config.tiles.spring_ext,
    archer     = level.special.archer     or config.tiles.archer,
    melee      = level.special.melee      or config.tiles.melee,
  }

  local ents = {
    arrows       = {},
    e_arrows     = {},
    enemies      = {},
    particles    = {},
    spawn_points = {},
    keys         = {},
    locks        = {},
    doors        = {},
    switches     = {},
    springs      = {},
  }

  -- ==== spawn points ====
  -- NOTE: the spawn may remain a marker tile in the tile layer (as in the
  -- current level); everything else is object-based. The marker scan uses
  -- the pico-8 cart spawn tile constant (preserved cart behaviour).
  local spawn_tile = config.tiles.spawn
  for r = 0, level.MAP_H - 1 do
    for c = 0, level.MAP_W - 1 do
      local row = level.map[r + 1]
      local t = row and tonumber(row:sub(c*2 + 1, c*2 + 2), 16) or 0
      if t == spawn_tile then
        table.insert(ents.spawn_points, {x = c*tw, y = r*tw})
      end
    end
  end
  for _, o in ipairs(level.objects) do
    if o.kind == "spawn" then
      table.insert(ents.spawn_points, {x = o.x, y = o.y})
    end
  end

  -- ==== enemies ====
  for _, o in ipairs(level.objects) do
    if o.kind == "archer" or o.kind == "melee" then
      local ex, ey = snap_tile(o.x, tw), snap_tile(o.y, tw)
      local e = {
        x = ex, y = ey,
        home_x = ex,  -- spawn anchor for the patrol roam limit
        vx = 0, vy = 0, w = cfg.width, h = cfg.height,
        gr = false, facing = 1, type = o.kind,
        shoot_cd = cfg.shoot_cooldown,
        spr = o.spr or ((o.kind == "melee") and tiles.melee or tiles.archer),
        rot = o.rot,
      }
      if o.kind == "archer" then
        -- sense -> aim -> volley -> investigate brain state
        e.state = "patrol"
        e.aim_t = 0
        e.last_known = nil
      end
      apply_object_props(e, o)
      table.insert(ents.enemies, e)
    end
  end

  -- ==== interactables ====
  for _, o in ipairs(level.objects) do
    local k = o.kind
    if k == "key" or k == "lock" or k == "door" or k == "switch"
    or k == "spring" then
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      if k == "key" then
        table.insert(ents.keys, {x = wx, y = wy, g = o.g, taken = false,
          spr = o.spr or tiles.key, rot = o.rot})
      elseif k == "lock" then
        table.insert(ents.locks, {x = wx, y = wy, g = o.g, triggered = false,
          spr = o.spr or tiles.lock, rot = o.rot})
      elseif k == "door" then
        table.insert(ents.doors, {x = wx, y = wy, g = o.g, open = false,
          tc = math.floor(wx/tw), tr = math.floor(wy/tw),
          spr = o.spr or tiles.door, rot = o.rot})
      elseif k == "switch" then
        table.insert(ents.switches, {x = wx, y = wy, g = o.g, on = false,
          spr = o.spr or tiles.switch, rot = o.rot})
      else
        table.insert(ents.springs, {x = wx, y = wy, g = o.g, ext = nil,
          spr = o.spr or tiles.spring, rot = o.rot})
      end
    end
  end

  return ents, tiles
end

return Level
