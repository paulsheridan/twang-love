-- Level assembly: turns a src/tiled.lua load result into the game's live
-- entity lists (spawns, enemies, arrows, particles) and the puzzle
-- interactables (keys/locks/doors/switches/springs) plus the mover blocks
-- (src/movers.lua).
--
-- Entities are Tiled objects (see src/tiled.lua): roles from the object's
-- kind/class, puzzle groups from names, extra custom properties override
-- entity defaults (per-instance tuning like shoot cooldowns). Entity art
-- and hit anchors stay on the 16px art grid (config.art_size) even
-- though the terrain grid is 8px.

local Util = require("src.util")

local Level = {}

-- Snaps an object's pixel position to the terrain grid (8px).
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
    winch      = level.special.winch      or config.tiles.winch,
    pusher     = level.special.pusher     or config.tiles.pusher,
    mover      = level.special.mover      or config.tiles.mover,
    exit       = level.special.exit       or config.tiles.exit,
    checkpoint = level.special.checkpoint or config.tiles.checkpoint,
    archer     = level.special.archer     or config.tiles.archer,
    melee      = level.special.melee      or config.tiles.melee,
    laser      = level.special.laser      or config.tiles.laser,
    rocketeer  = level.special.rocketeer  or config.tiles.rocketeer,
    bomber     = level.special.bomber     or config.tiles.bomber,
  }

  local ents = {
    arrows       = {},
    e_arrows     = {},
    enemies      = {},
    rockets      = {},
    bombs        = {},
    booms        = {},
    burns        = {},
    guns         = {},  -- dropped guns (laser kills; pickup = one explosive shot)
    -- the spirit arrow fires no projectile (src/spirit.lua runs at
    -- fire time only), so unlike the bomb arrow there is no list
    particles    = {},
    spawn_points = {},
    keys         = {},
    locks        = {},
    doors        = {},
    switches     = {},
    springs      = {},
    winches      = {},
    pushers      = {},
    movers       = {},
    exits        = {},
    checkpoints  = {},
  }

  -- ==== spawn points ====
  -- NOTE: the spawn may remain a marker tile in the tile layer (as in the
  -- current level); everything else is object-based. The marker scan uses
  -- the pico-8 cart spawn label constant (preserved cart behaviour) and
  -- matches any of the marker art's four 8px sub-tiles.
  local spawn_tile = config.tiles.spawn
  local seen = {}
  for r = 0, level.MAP_H - 1 do
    for c = 0, level.MAP_W - 1 do
      local row = level.map[r + 1]
      local t = row and tonumber(row:sub(c*4 + 1, c*4 + 4), 16) or 0
      if t ~= 0
      and math.floor((t % 32) / 2) + math.floor(t / 64) * 16 == spawn_tile then
        -- one point per 16px marker art cell (its four sub-cells all
        -- match; the map carries them as one subdivided marker)
        local key = math.floor(c / 2) .. "," .. math.floor(r / 2)
        if not seen[key] then
          seen[key] = true
          table.insert(ents.spawn_points, {x = c*tw, y = r*tw})
        end
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
    if o.kind == "archer" or o.kind == "melee" or o.kind == "laser"
    or o.kind == "rocketeer" or o.kind == "bomber" then
      local ex, ey = snap_tile(o.x, tw), snap_tile(o.y, tw)
      local e = {
        x = ex, y = ey,
        home_x = ex,  -- spawn anchor for the patrol roam limit
        vx = 0, vy = 0, w = cfg.width, h = cfg.height,
        gr = false, facing = 1, type = o.kind,
        shoot_cd = cfg.shoot_cooldown,
        spr = o.spr or ((o.kind == "melee") and tiles.melee
          or (o.kind == "laser") and tiles.laser
          or (o.kind == "rocketeer") and tiles.rocketeer
          or (o.kind == "bomber") and tiles.bomber or tiles.archer),
        rot = o.rot,
      }
      -- every brain starts on patrol with nothing tracked yet; the
      -- ranged brains also carry an aim telegraph timer
      e.state = "patrol"
      e.last_known = nil
      if o.kind == "archer" or o.kind == "laser" or o.kind == "rocketeer"
      or o.kind == "bomber" then
        e.aim_t = 0
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
          spr = o.spr or tiles.switch, rot = o.rot,
          -- switches flagged "phase" drive the level's phase tiles; other
          -- switches leave the blocks alone (only their group's doors
          -- and springs react to them)
          phase = o.phase and true or nil})
      else
        table.insert(ents.springs, {x = wx, y = wy, g = o.g, ext = nil,
          spr = o.spr or tiles.spring, rot = o.rot})
      end
    elseif k == "winch" then
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      table.insert(ents.winches, {x = wx, y = wy, g = o.g,
        spr = o.spr or tiles.winch, rot = o.rot})
    elseif k == "gun" then
      -- a placed gun pickup (an authoring tool for tests/demo maps):
      -- acts exactly like a dropped one
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      table.insert(ents.guns, { x = wx, y = wy, g = o.g, taken = false,
        spr = o.spr, rot = o.rot })
    elseif k == "pusher" or k == "updraft" or k == "outdraft" then
      -- the pusher family owns its 16px block (a solid 2x2-cell run,
      -- like a door): the cell column/row come from the snapped
      -- position. The kind IS
      -- the variant ("updraft" launches straight up, "outdraft" drains
      -- a cone above it up-and-away); legacy "pusher" objects default
      -- to the updraft behaviour.
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      local e = {x = wx, y = wy, g = o.g,
        tc = math.floor(wx/tw), tr = math.floor(wy/tw),
        variant = k == "pusher" and "updraft" or k,
        spr = o.spr or tiles.pusher, rot = o.rot}
      -- per-instance overrides (push, reach, side, cone, radius,
      -- shove_grace) ride the object props
      for _, prop in ipairs({"push", "radius", "shove_grace",
                             "reach", "side", "cone"}) do
        if o[prop] ~= nil then e[prop] = o[prop] end
      end
      table.insert(ents.pushers, e)
    elseif k == "mover" or k == "mover_trigger" or k == "movertrigger" then
      -- the moving block (src/movers.lua): a solid block of tiles that
      -- travels back and forth along a tile-aligned line from its rest
      -- position. The line's DIRECTION is the explicit `dir` property
      -- (up / down / left / right) — nothing about the block's shape
      -- implies it, so a block of any footprint can run any way — for
      -- the `distance` (tiles) property's length, rest position first:
      -- at distance 4 pointing right the block starts at its object
      -- top-left and runs right, pausing 4 tiles over. `distance` AND
      -- `dir` are both required (a mover without either is skipped
      -- with a warning). Per-instance speed/pause overrides ride the
      -- object props.
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      local dist_tiles = math.floor(tonumber(o.distance or 0))
      local dirs = {
        right = { 1, 0 }, left = { -1, 0 },
        up = { 0, -1 }, down = { 0, 1 },
      }
      local d = o.dir and dirs[tostring(o.dir):lower()]
      if not dist_tiles or dist_tiles <= 0 then
        print("level: warning - mover '" .. tostring(o.name)
          .. "' has no usable `distance` property (tiles); skipped")
      elseif not d then
        print("level: warning - mover '" .. tostring(o.name)
          .. "' has no usable `dir` property (up/down/left/right); skipped")
      else
        -- footprint: explicit `tiles_w`/`tiles_h` (int art tiles)
        -- properties win; otherwise the object's own placed size
        -- (o.ow/o.oh, from resizing it in Tiled) rounds to art tiles;
        -- clamped 1..3 each way. Art tiles are 16px cells
        -- (config.art_size) even though the map grid is 8px.
        local cfg = config.mover
        local art = config.art_size
        local wt = math.max(1, math.min(cfg.max_tiles,
          tonumber(o.tiles_w)
            or math.floor((o.ow or art) / art + 0.5)))
        local ht = math.max(1, math.min(cfg.max_tiles,
          tonumber(o.tiles_h)
            or math.floor((o.oh or art) / art + 0.5)))
        local dx, dy = d[1], d[2]
        local m = {
          mode = k == "mover" and "auto" or "trigger",
          ox = wx, oy = wy,   -- rest (A end) top-left, px
          dx = dx, dy = dy,   -- the line's direction (one tile step)
          len = dist_tiles * tw, -- line length, px
          wt = wt, ht = ht,   -- footprint, art tiles
          bw = wt * art, bh = ht * art,
          bx = wx, by = wy,   -- the block's current box top-left, px
          px = 0,             -- progress along the line, tiles
          dirn = 1,           -- outward (+1) / homeward (-1)
          state = "rest",     -- rest -> go -> pause -> go ...
          vel = 0,            -- the block's live world x-velocity, px/step
          t = 0, f = 0,       -- timers: pause steps, whole-pixel bank
          g = o.g, name = o.name,
          spr = o.spr or tiles.mover, rot = o.rot,
        }
        for _, prop in ipairs({"speed", "pause", "pause_steps"}) do
          if o[prop] ~= nil then m[prop] = o[prop] end
        end
        if m.pause_steps == nil and m.pause ~= nil then
          m.pause_steps = m.pause
          m.pause = nil
        end
        table.insert(ents.movers, m)
      end
    elseif k == "exit" then
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      table.insert(ents.exits, {x = wx, y = wy,
        spr = o.spr or tiles.exit, rot = o.rot})
    elseif k == "checkpoint" then
      local wx, wy = snap_tile(o.x, tw), snap_tile(o.y, tw)
      table.insert(ents.checkpoints, {x = wx, y = wy,
        spr = o.spr or tiles.checkpoint, rot = o.rot})
    end
  end

  return ents, tiles
end

return Level
