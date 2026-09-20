-- The tile world: grid storage, per-tile flags, solidity queries and
-- terrain (slope) collision.
--
-- The grid is stored as one hex byte per tile, row-major (the pico-8 cart's
-- mget format, produced by src/tiled.lua). Tile flags come from the Tiled
-- tileset's custom properties, packed into per-tile flag bytes:
--   bit 0 solid  bit 1 sticky  bit 2 friction (slippery)  bit 3 arrow_pass
--
-- Doors, springs and switches own tile solidity in special ways (see
-- solid_at / solid_for_arrow); they are referenced from the level's
-- entity lists, passed in at construction.
--
-- Phase tiles (tileset property "phase", e.g. platforms struck through
-- by switch toggles) flip all instances solid<->non-solid together via
-- World.phase_solid; see solid_at and Interactables.toggle_phase_tiles.

local config = require("src.config")

local World = {}
World.__index = World

--- Builds a world from a src/tiled.lua load result plus the level's
--- interactable entity lists (doors/springs/switches).
function World.new(level, ents, tile_size)
  local self = setmetatable({}, World)
  self.map       = level.map
  self.w         = level.MAP_W
  self.h         = level.MAP_H
  self.px_w      = level.MAP_W * tile_size
  self.px_h      = level.MAP_H * tile_size
  self.gff       = level.gff
  self.slope_type = level.slope_type
  self.tw        = tile_size
  self.doors     = ents.doors
  self.springs   = ents.springs
  self.switches  = ents.switches
  self.phase_tiles = level.phase_tiles or {}
  self.phase_solid = true  -- phase tiles start solid; phase-switch strikes flip this
  -- visual-only named Tiled layers (see docs/tiled-format.md): the
  -- backdrop draws behind everything; the foreground overlay draws on
  -- top of the player and fades out as a whole while they walk behind it
  self.bg_map   = level.background
  self.fg_map   = level.foreground
  self.fg_alpha = 1    -- foreground layer's current draw alpha
  return self
end

-- ==== tile access ====

-- Tile id at column c, row r; 0 outside the map.
function World:tile(c, r)
  if c < 0 or c >= self.w or r < 0 or r >= self.h then return 0 end
  local row = self.map[r + 1]
  return row and tonumber(row:sub(c*2 + 1, c*2 + 2), 16) or 0
end

-- Tile id on a visual-only named layer (nil grid -> 0 everywhere).
local function layer_tile(rows, w, h, c, r)
  if not rows or c < 0 or c >= w or r < 0 or r >= h then return 0 end
  local row = rows[r + 1]
  return row and tonumber(row:sub(c*2 + 1, c*2 + 2), 16) or 0
end

function World:bg_tile(c, r)
  return layer_tile(self.bg_map, self.w, self.h, c, r)
end

function World:fg_tile(c, r)
  return layer_tile(self.fg_map, self.w, self.h, c, r)
end

function World:set_tile(c, r, t)
  if c < 0 or c >= self.w or r < 0 or r >= self.h then return end
  self.map[r + 1] = self.map[r + 1]:sub(1, c*2)
    .. string.format("%02x", t)
    .. self.map[r + 1]:sub(c*2 + 3)
end

-- Tile flag bit f (from the Tiled tileset's custom properties).
function World:flag(t, f)
  if t <= 0 then return false end
  return math.floor(self.gff[t + 1] / 2^f) % 2 == 1
end

function World:solid(t)        return t ~= 0 and self:flag(t, 0) end
function World:sticky(t)       return t ~= 0 and self:flag(t, 1) end
function World:arrow_pass(t)   return t ~= 0 and self:flag(t, 3) end

-- Is this tile id one of the switch-flipped phase tiles?
function World:is_phase(t)
  return t ~= 0 and self.phase_tiles[t] == true
end

-- Friction scale for a tile: slippery tiles slow movement, all others
-- are normal ground.
function World:friction(t)
  return (t ~= 0 and self:flag(t, 2)) and config.player.slippery_friction or 1.0
end

-- ==== foreground overlay fade ====

-- One sim step of the foreground overlay's fade (runs in world time:
-- `dt` is the step's world-time scale, so the fade slows with aiming's
-- slow motion like everything else). While the player's box (grown by
-- the fade margin) touches any overlay tile the whole layer eases to
-- invisible -- buildings and hidden spaces vanish together, so the
-- avatar stays readable -- and it eases back once they step out.
function World:foreground_step(player, dt)
  if not self.fg_map or not player then return end
  local cfg = config.foreground
  local tw = self.tw
  -- the player's box grown by the fade margin, in tile columns/rows
  local c0 = math.floor((player.x - cfg.fade_margin_px) / tw)
  local c1 = math.floor((player.x + player.w - 1 + cfg.fade_margin_px) / tw)
  local r0 = math.floor((player.y - cfg.fade_margin_px) / tw)
  local r1 = math.floor((player.y + player.h - 1 + cfg.fade_margin_px) / tw)
  -- behind = any overlay tile in that band
  local behind = false
  for r = r0, r1 do
    for c = c0, c1 do
      if self:fg_tile(c, r) ~= 0 then
        behind = true
        break
      end
    end
    if behind then break end
  end
  local target = behind and 0 or 1
  local k = cfg.fade_alpha_step * (dt or 1)
  local a = self.fg_alpha
  if a < target then
    self.fg_alpha = math.min(a + k, target)
  else
    self.fg_alpha = math.max(a - k, target)
  end
end

-- ==== solidity queries ====

function World:solid_at(x, y)
  local c, r = math.floor(x/self.tw), math.floor(y/self.tw)
  -- doors own their tile: a door object placed over terrain (doorway
  -- art and the like) governs that tile's solidity by itself
  for _, d in ipairs(self.doors) do
    if d.tc == c and d.tr == r then return not d.open end
  end
  -- springs are standable pads: only the pad's bottom band is solid (the
  -- inactive spring sprite occupies the tile's lower half, so a full-tile
  -- hitbox makes bodies hover), and they stand even in gaps in the floor
  for _, s in ipairs(self.springs) do
    if math.floor(s.x/self.tw) == c and math.floor(s.y/self.tw) == r then
      return y >= s.y + self.tw - config.springs.pad_height
    end
  end
  local t = self:tile(c, r)
  -- phase tiles are switch-flipped: while the phase is off they stop
  -- blocking anything (this covers arrows too, via solid_for_arrow)
  if t ~= 0 and self:solid(t)
  and not (self:is_phase(t) and not self.phase_solid) then
    return true
  end
  return false
end

-- Arrows (player and enemy) ignore arrow-pass tiles, so arrow slits let
-- shots through while walls still block the player and enemies.
function World:solid_for_arrow(x, y)
  local c, r = math.floor(x/self.tw), math.floor(y/self.tw)
  for _, d in ipairs(self.doors) do
    if d.tc == c and d.tr == r then return not d.open end
  end
  -- switch tiles are recessed: arrows fly into them and strike the
  -- switch, while the player and enemies are still blocked
  for _, s in ipairs(self.switches) do
    if math.floor(s.x/self.tw) == c and math.floor(s.y/self.tw) == r then
      return false
    end
  end
  local t = self:tile(c, r)
  if t ~= 0 and self:arrow_pass(t) then return false end
  return self:solid_at(x, y)
end

function World:sticky_at(x, y)
  local c, r = math.floor(x/self.tw), math.floor(y/self.tw)
  -- a closed door is a bouncy surface, like a sticky wall: doors are
  -- temporary solids, so an arrow embedded in one would be left hanging
  -- in the doorway the moment a switch opens it
  for _, d in ipairs(self.doors) do
    if d.tc == c and d.tr == r then return not d.open end
  end
  local t = self:tile(c, r)
  return t ~= 0 and self:sticky(t)
end

-- Open-fall depth below (x, y): the px distance down to the first ground
-- tile directly beneath, capped at max_px (math.huge when there is no
-- ground within that range). Used by investigating archers to decide
-- whether a ledge drop is worth stepping off.
function World:drop_depth(x, y, max_px)
  local d = 0
  while d < max_px do
    d = d + self.tw
    if self:solid_at(x, y + d) or self:in_slope_solid(x, y + d) then
      return d
    end
  end
  return math.huge
end

-- ==== slopes ====

-- Slope shapes (set from the tileset's "slope" property): 1 / floor,
-- 2 \ floor, 3 \ ceiling, 4 / ceiling.

-- Height of a floor slope's surface at world x (within tile column).
function World:slope_floor_y(st, tr, wx)
  local sx = math.floor(wx) % self.tw
  return tr*self.tw + (st == 1 and (self.tw - 1 - sx) or sx)
end

function World:slope_ceil_y(st, tr, wx)
  local sx = math.floor(wx) % self.tw
  return tr*self.tw + (st == 3 and sx or (self.tw - 1 - sx))
end

-- True when the point (x, y) is inside a slope tile's solid wedge.
function World:in_slope_solid(x, y)
  local tc = math.floor(x/self.tw)
  local tr = math.floor(y/self.tw)
  local st = self.slope_type[self:tile(tc, tr)]
  if not st then return false end
  local sx = math.floor(x) % self.tw
  local TW = self.tw
  if     st == 1 then return y >= tr*TW + (TW - 1 - sx)
  elseif st == 2 then return y >= tr*TW + sx
  elseif st == 3 then return y <= tr*TW + sx
  else                return y <= tr*TW + (TW - 1 - sx)
  end
end

-- Snaps a body onto floor/ceiling slopes it overlaps (both feet corners
-- sampled; the slope wins over tile solidity). The floor pass also looks
-- one tile ABOVE the feet, so a body walking along flat ground steps up
-- onto a rising slope instead of walking under its wedge. A candidate
-- snap is rejected when it would leave the body inside a solid tile
-- (where a wedge meets flat ground); the resolve_y position stands.
function World:resolve_slopes(obj)
  local by = obj.y + obj.h
  if obj.vy >= -1 then
    local lx = obj.x + 2
    local rx = obj.x + obj.w - 4
    local snapped = false
    for _, fx in ipairs({lx, rx}) do
      if snapped then break end
      -- at the feet, below them (fell one tile past a slope) and above
      -- them (step up onto the slope from the flat ground beneath)
      for _, dy in ipairs({0, self.tw, -self.tw}) do
        if snapped then break end
        local tc = math.floor(fx/self.tw)
        local tr = math.floor((by+dy)/self.tw)
        local st = self.slope_type[self:tile(tc, tr)]
        if st and st <= 2 then
          local sy = self:slope_floor_y(st, tr, fx)
          if by >= sy-4 and by <= sy+self.tw
          and not self:solid_at(obj.x, sy-1)
          and not self:solid_at(obj.x+obj.w-1, sy-1)
          and not self:solid_at(obj.x, sy-obj.h)
          and not self:solid_at(obj.x+obj.w-1, sy-obj.h) then
            obj.y = sy - obj.h
            if obj.vy > 0 then obj.vy = 0 end
            obj.gr = true
            obj.fr = 1.0
            snapped = true
          end
        end
      end
    end
  end
  if obj.vy < 0 then
    local lx = obj.x + 2
    local rx = obj.x + obj.w - 4
    for _, fx in ipairs({lx, rx}) do
      local tc = math.floor(fx/self.tw)
      local tr = math.floor(obj.y/self.tw)
      local st = self.slope_type[self:tile(tc, tr)]
      if st and st >= 3 then
        local cy = self:slope_ceil_y(st, tr, fx)
        if obj.y <= cy then
          obj.y  = cy
          obj.vy = 0
          break
        end
      end
    end
  end
end

-- ==== collision passes ====

-- A slope's floor surface near the body's centre masks a false-positive
-- wall hit from resolve_x (stepping up a / or \ floor slope).
function World:shielded_by_slope(obj, y)
  local cx = obj.x + obj.w / 2
  local tc = math.floor(cx / self.tw)
  for tr = math.floor(y/self.tw)-1, math.floor(y/self.tw) do
    local st = self.slope_type[self:tile(tc, tr)]
    if st and st <= 2 then
      if self:slope_floor_y(st, tr, cx) <= y + 1 then return true end
    end
  end
  return false
end

-- Standing surface (top y) of a spring pad, when the point (x, y) lies
-- within a spring's solid pad band; nil otherwise. resolve_y uses it to
-- land bodies on the pad itself instead of the tile's top edge.
function World:spring_stand_y(x, y)
  local pad = config.springs.pad_height
  for _, s in ipairs(self.springs) do
    if x >= s.x and x < s.x + self.tw
    and y >= s.y + self.tw - pad and y <= s.y + self.tw then
      return s.y + self.tw - pad
    end
  end
  return nil
end

function World:resolve_x(obj)
  if obj.vx > 0 then
    local rx = obj.x + obj.w - 1
    local hit_top = self:solid_at(rx, obj.y)
    local hit_bot = self:solid_at(rx, obj.y+obj.h-1)
    if hit_bot and not hit_top and self:shielded_by_slope(obj, obj.y+obj.h-1) then
      hit_bot = false
    end
    if hit_top or hit_bot then
      obj.x  = math.floor(rx/self.tw)*self.tw - obj.w
      obj.vx = 0
    end
  elseif obj.vx < 0 then
    local hit_top = self:solid_at(obj.x, obj.y)
    local hit_bot = self:solid_at(obj.x, obj.y+obj.h-1)
    if hit_bot and not hit_top and self:shielded_by_slope(obj, obj.y+obj.h-1) then
      hit_bot = false
    end
    if hit_top or hit_bot then
      obj.x  = (math.floor(obj.x/self.tw)+1)*self.tw
      obj.vx = 0
    end
  end
end

function World:resolve_y(obj)
  if obj.vy >= 0 then
    local by = obj.y + obj.h
    if self:solid_at(obj.x, by) or self:solid_at(obj.x+obj.w-1, by) then
      -- spring pads: land on the pad's surface, not the tile's top edge
      local stand = self:spring_stand_y(obj.x, by)
                 or self:spring_stand_y(obj.x + obj.w - 1, by)
      local tc = self:tile(math.floor(obj.x/self.tw), math.floor(by/self.tw))
      obj.y  = stand and stand - obj.h
                    or math.floor(by/self.tw)*self.tw - obj.h
      obj.vy = 0
      obj.gr = true
      obj.fr = self:friction(tc)
    end
  elseif obj.vy < 0 then
    local hx_left  = self:solid_at(obj.x, obj.y)
    local hx_right = self:solid_at(obj.x+obj.w-1, obj.y)
    if hx_left or hx_right then
      -- corner forgiveness: exactly one head corner clipped the edge of
      -- a ceiling tile — slide horizontally around it (within
      -- corner_nudge_px) when the beside space is open, so a jump taken
      -- under a ledge keeps its full height. Covered corners or a
      -- blocked/nudge-over-cap slide fall back to the bump below.
      local shifted = false
      if hx_right and not hx_left then
        local shift = obj.x + obj.w
                    - math.floor((obj.x+obj.w-1)/self.tw)*self.tw
        if shift <= config.player.corner_nudge_px
        and not self:solid_at(obj.x - shift, obj.y)
        and not self:solid_at(obj.x - shift + obj.w - 1, obj.y) then
          obj.x, shifted = obj.x - shift, true
        end
      elseif hx_left and not hx_right then
        local shift = (math.floor(obj.x/self.tw)+1)*self.tw - obj.x
        if shift <= config.player.corner_nudge_px
        and not self:solid_at(obj.x + shift, obj.y)
        and not self:solid_at(obj.x + shift + obj.w - 1, obj.y) then
          obj.x, shifted = obj.x + shift, true
        end
      end
      if not shifted then
        obj.y  = (math.floor(obj.y/self.tw)+1)*self.tw
        obj.vy = 0
      end
    end
  end
end

-- Senses walls adjacent to a body's sides (wall-slide input gating).
function World:check_walls(obj)
  obj.wall_l, obj.wall_r = false, false
  if obj.gr then return end
  local tr = math.floor(obj.y/self.tw)
  local br = math.floor((obj.y+obj.h-1)/self.tw)
  for r = tr, br do
    if self:solid(self:tile(math.floor((obj.x-1)/self.tw), r)) then
      obj.wall_l = true
    end
    if self:solid(self:tile(math.floor((obj.x+obj.w)/self.tw), r)) then
      obj.wall_r = true
    end
  end
end

return World
