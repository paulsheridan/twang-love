-- twang: archer side-scroller
-- love2d port of twang.p8
-- 240x160 native rendering, 30hz fixed-timestep sim, smooth camera
-- levels are Tiled JSON maps (see tiled.lua for the editing conventions)

local tiled = require("tiled")

-- ===== constants =====
local grav    = 0.28
local jforc   = -3.2   -- jump velocity
local pspd    = 1.5    -- max walk speed
local paccel  = 0.30
local pdecel  = 0.24
local air     = 0.6
local coy_t   = 8
local jbuf_t  = 8
local pw, ph  = 4, 6
local TW      = 8

-- view / world (world size comes from the Tiled map at load time)
local VW, VH  = 240, 160
local MAP_FILE = "maps/level1.json"
local MAP_W, MAP_H = 128, 30
local ww, wh  = MAP_W * TW, MAP_H * TW

-- jump system
local j_frames_max = 6
local j_iacc  = 1.8
local j_acc   = 0.9

-- arrow mode
local max_arr = 3
-- speed scaled 1.5x over the cart with gravity scaled 1.5^2: the arc
-- shape and range stay identical, just flown faster
local arrow_cfg = {spd=8.25, grv=0.2025, col=10}
local arrow_spds = {4.5, 6.75, 9.0}
local BOUNCE_MAX = 2    -- surviving bounces off sticky surfaces...
local DIE_FRAMES = 12   -- ...then the next bounce spins out and vanishes
local DIE_SPIN   = 0.45 -- spin-out rotation, rad per frame
local SLOW_N   = 12
local slow_cnt = 0

-- run cycle (advances at 30hz sim rate; see upd_player_phys)
local run_frame, run_tick = 0, 0

-- enemy constants
local MELEE_SPD   = 0.6
local ARCHER_SPD  = 0.4
local DETECT_DIST = 80
local SHOOT_CD    = 90
local BLOOD_N     = 10
-- special map tiles: kept only as the fallback SPRITE indices for
-- interactables whose object did not place a recognizable tile
-- (the pico-8 cart values)
local TILE_SPAWN, TILE_KEY = 63, 70
local TILE_LOCK   = 71
local TILE_DOOR   = 72

-- ===== pico-8 palette =====
local PAL = {
  [0]={0,0,0},{29,43,83},{126,37,83},{0,135,81},{171,82,54},
  {95,87,79},{194,195,199},{255,241,232},{255,0,77},{255,163,0},
  {255,236,39},{0,228,54},{41,173,255},{131,118,156},{255,119,168},
  {255,204,170},
}
local function pcol(c)
  local rgb = PAL[c] or PAL[0]
  return rgb[1]/255, rgb[2]/255, rgb[3]/255, 1
end

-- aim angles use the pico-8 convention: fractions of a full turn (0..1),
-- 0=right, 0.25=down, 0.5=left, 0.75=up. convert to radians for math.sin/cos
local TAU = math.pi * 2
local function p8sin(a) return math.sin(a * TAU) end
local function p8cos(a) return math.cos(a * TAU) end

-- ===== map access =====
local map, gff
local function mget(c, r)
  if c < 0 or c >= MAP_W or r < 0 or r >= MAP_H then return 0 end
  local row = map[r + 1]
  return row and tonumber(row:sub(c*2+1, c*2+2), 16) or 0
end

local function mset(c, r, t)
  if c < 0 or c >= MAP_W or r < 0 or r >= MAP_H then return end
  map[r + 1] = map[r + 1]:sub(1, c*2) .. string.format("%02x", t) .. map[r + 1]:sub(c*2+3)
end

local function fget(t, f)
  if t <= 0 then return false end
  return math.floor(gff[t+1] / 2^f) % 2 == 1
end

local function tile_solid(t)       return t ~= 0 and fget(t, 0) end
local function tile_arrow_pass(t)  return t ~= 0 and fget(t, 3) end
local function tile_sticky(t)   return t ~= 0 and fget(t, 1) end
local function tile_friction(t) return (t ~= 0 and fget(t, 2)) and 0.1 or 1.0 end

-- ===== interactables / world state =====
local arrows, p, cam
local enemies, e_arrows, particles, spawn_points
local keys, locks, doors, switches, springs

function solid_at(x, y)
  local c, r = math.floor(x/TW), math.floor(y/TW)
  -- doors own their tile: a door object placed over terrain (doorway
  -- art and the like) governs that tile's solidity by itself
  for _, d in ipairs(doors) do
    if d.tc == c and d.tr == r then return not d.open end
  end
  -- springs are standable pads: solid wherever they are placed, even in
  -- gaps in the floor terrain
  for _, s in ipairs(springs) do
    if math.floor(s.x/TW) == c and math.floor(s.y/TW) == r then
      return true
    end
  end
  local t = mget(c, r)
  if t ~= 0 and tile_solid(t) then return true end
  return false
end

-- arrows (player and enemy) ignore arrow-pass tiles, so arrow slits let
-- shots through while walls still block the player and enemies
function solid_for_arrow(x, y)
  local c, r = math.floor(x/TW), math.floor(y/TW)
  for _, d in ipairs(doors) do
    if d.tc == c and d.tr == r then return not d.open end
  end
  -- switch tiles are recessed: arrows fly into them and strike the
  -- switch, while the player and enemies are still blocked
  for _, s in ipairs(switches) do
    if math.floor(s.x/TW) == c and math.floor(s.y/TW) == r then
      return false
    end
  end
  local t = mget(c, r)
  if t ~= 0 and tile_arrow_pass(t) then return false end
  return solid_at(x, y)
end

local function sticky_at(x, y)
  local t = mget(math.floor(x/TW), math.floor(y/TW))
  return t ~= 0 and fget(t, 1)
end

-- ===== slope helpers =====
local slope_type = {
  [6]=1,[13]=1,   -- / floor
  [7]=2,[14]=2,   -- \ floor
  [54]=3,[61]=3,  -- \ ceil
  [55]=4,[62]=4,  -- / ceil
}

local function slope_floor_y(st, tr, wx)
  local sx = math.floor(wx) % TW
  return tr*TW + (st==1 and (TW-1-sx) or sx)
end

local function slope_ceil_y(st, tr, wx)
  local sx = math.floor(wx) % TW
  return tr*TW + (st==3 and sx or (TW-1-sx))
end

local function in_slope_solid(x, y)
  local tc = math.floor(x/TW)
  local tr = math.floor(y/TW)
  local st = slope_type[mget(tc, tr)]
  if not st then return false end
  local sx = math.floor(x) % TW
  if     st==1 then return y >= tr*TW + (TW-1-sx)
  elseif st==2 then return y >= tr*TW + sx
  elseif st==3 then return y <= tr*TW + sx
  else              return y <= tr*TW + (TW-1-sx)
  end
end

local function resolve_slopes(obj)
  local by = obj.y + obj.h
  if obj.vy >= -1 then
    local lx = obj.x + 1
    local rx = obj.x + obj.w - 2
    local snapped = false
    for _, fx in ipairs({lx, rx}) do
      if snapped then break end
      for _, dy in ipairs({0, TW}) do
        if snapped then break end
        local tc = math.floor(fx/TW)
        local tr = math.floor((by+dy)/TW)
        local st = slope_type[mget(tc, tr)]
        if st and st <= 2 then
          local sy = slope_floor_y(st, tr, fx)
          if by >= sy-2 and by <= sy+TW then
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
    local lx = obj.x + 1
    local rx = obj.x + obj.w - 2
    for _, fx in ipairs({lx, rx}) do
      local tc = math.floor(fx/TW)
      local tr = math.floor(obj.y/TW)
      local st = slope_type[mget(tc, tr)]
      if st and st >= 3 then
        local cy = slope_ceil_y(st, tr, fx)
        if obj.y <= cy then
          obj.y  = cy
          obj.vy = 0
          break
        end
      end
    end
  end
end

local function mv_to(v, target, step)
  if v < target then return math.min(v + step, target)
  else               return math.max(v - step, target)
  end
end

local function aabb(a, b)
  return a.x < b.x+b.w and a.x+a.w > b.x
     and a.y < b.y+b.h and a.y+a.h > b.y
end

-- ===== input (pico buttons 0..5) =====
-- keyboard: arrows + z (aim) + x (jump); m/tab opens the controls panel
-- gamepad (any SDL gamepad):
--   dpad / left stick -> move
--   A                 -> jump
--   right bumper/RT   -> aim (left stick aims while held)
--   start             -> controls panel    back -> quit
-- held state is polled once per rendered frame, but press edges (btnp) are
-- evaluated per sim step (30hz) so a press landing on a frame with no step
-- is never swallowed -- that race was what made jumping unreliable. Press
-- events also latch, so taps shorter than one rendered frame still fire
-- (matching pico-8's 30hz-sampled behaviour). btnp uses pico-8 key repeat
-- (every 4 frames after 15 held).
local held, hold_cnt = {}, {}
local press_latch, press_edge = {}, {}
local keymap = {
  left  = 0, right = 1, up = 2, down = 3,
  z     = 4, x     = 5,
}
local gpmap = {
  dpleft = 0, dpright = 1, dpup = 2, dpdown = 3,
  a = 5, b = 5,      -- jump
  rightshoulder = 4, -- aim
}
local function btn(i) return held[i] end

-- recompute per-step press edges; call once at the top of each sim step
local function tick_held()
  for i = 0, 5 do
    hold_cnt[i] = held[i] and (hold_cnt[i] or 0) + 1 or 0
    press_edge[i] = (held[i] and hold_cnt[i] == 1)
                 or (hold_cnt[i] >= 16 and (hold_cnt[i] - 16) % 4 == 0)
                 or press_latch[i] or false
    press_latch[i] = false  -- event latches are consumed by the next step
  end
end

-- pico-8 btnp: true on the press frame, then every 4 frames after 15 held
local function btnp(i) return press_edge[i] end

-- ===== controls (modern style) =====
-- keyboard: arrows + z (aim) + x (jump); arrows left/right rotate the bow,
--           up/down set power
-- gamepad:  dpad/left stick moves; while the aim button is held the left
--           stick aims the bow (dpad left/right nudges when the stick is
--           idle); power comes from keyboard up/down or the REAL dpad
--           only, so pushing the analog stick can't toggle it
--           A jumps; right bumper / right trigger aim
local menu_open = false  -- control panel; kept for future settings

-- left-stick direction, if pushed past the deadzone (analog aiming)
local function aim_stick_vec()
  for _, pad in ipairs(love.joystick.getJoysticks()) do
    if pad:isGamepad() then
      local x = pad:getGamepadAxis("leftx") or 0
      local y = pad:getGamepadAxis("lefty") or 0
      if x*x + y*y > 0.09 then return x, y end  -- deadzone 0.3
    end
  end
  return nil, nil
end

local function poll_gamepad()
  -- out[1..4] movement (dpad or stick), out[5] aim, out[6] jump --
  -- aligned with the button indices in refresh_held (held[4]=aim,
  -- held[5]=jump). dpad returns the PHYSICAL dpad only, without the
  -- stick, so up/down can drive power without stick interference.
  local out  = {false, false, false, false, false, false}
  local dpad = {false, false, false, false}
  for _, pad in ipairs(love.joystick.getJoysticks()) do
    if pad:isGamepad() then
      dpad[1] = dpad[1] or pad:isGamepadDown("dpleft")
      dpad[2] = dpad[2] or pad:isGamepadDown("dpright")
      dpad[3] = dpad[3] or pad:isGamepadDown("dpup")
      dpad[4] = dpad[4] or pad:isGamepadDown("dpdown")
      out[1] = out[1] or dpad[1] or (pad:getGamepadAxis("leftx") or 0) < -0.5
      out[2] = out[2] or dpad[2] or (pad:getGamepadAxis("leftx") or 0) >  0.5
      out[3] = out[3] or dpad[3] or (pad:getGamepadAxis("lefty") or 0) < -0.5
      out[4] = out[4] or dpad[4] or (pad:getGamepadAxis("lefty") or 0) >  0.5
      -- A / B jump; right bumper / right trigger aim
      if pad:isGamepadDown("rightshoulder") then out[5] = true end
      local rt = pad:getGamepadAxis("triggerright")
      if rt and rt > 0.4 then out[5] = true end
      if pad:isGamepadDown("a") or pad:isGamepadDown("b") then out[6] = true end
    else
      -- raw-fallback controllers: buttons 14-17 dpad, 12/13 face
      if pad:isDown(14) then out[1]  = true dpad[1] = true end
      if pad:isDown(15) then out[2]  = true dpad[2] = true end
      if pad:isDown(16) then out[3]  = true dpad[3] = true end
      if pad:isDown(17) then out[4]  = true dpad[4] = true end
      if pad:isDown(10) or pad:isDown(11) then out[5] = true end
      if pad:isDown(12) or pad:isDown(13) then out[6] = true end
    end
  end
  return out, dpad
end

local function refresh_held()
  local nh = {}
  for k, i in pairs(keymap) do
    nh[i] = love.keyboard.isDown(k)
  end
  local gp, dpad = poll_gamepad()
  held[0] = (nh[0] or gp[1]) and true or false
  held[1] = (nh[1] or gp[2]) and true or false
  -- up/down drive power: keyboard or physical dpad only, never the stick
  held[2] = (nh[2] or dpad[3]) and true or false
  held[3] = (nh[3] or dpad[4]) and true or false
  held[4] = (nh[4] or gp[5]) and true or false
  held[5] = (nh[5] or gp[6]) and true or false
end

-- ===== init / respawn =====
local function respawn()
  local sp = spawn_points[math.random(#spawn_points)]
  p = {
    x = sp and sp.x or 4,
    y = sp and sp.y or 82,
    vx=0, vy=0, w=pw, h=ph,
    gr=false, facing=1, coy=0, jbuf=0, fr=1.0,
    j_frames=0,
    wall_l=false, wall_r=false,
    aim_angle=0, aim_power=2, was_aiming=false, aimed_down=false,
    prev_gr=false, land_frames=0,
    key=nil,  -- carried key object (taken from the world or an arrow)
  }
  -- snap camera to the spawn point (pico-8 snapped per screen; no slow pan)
  if cam then
    cam.x = math.max(0, math.min(ww - VW, p.x + p.w/2 - VW/2))
    cam.y = math.max(0, math.min(wh - VH, p.y + p.h/2 - VH/2))
  end
end

-- entities are Tiled objects (see tiled.lua): roles from the object's
-- kind/class, puzzle groups from names, extra properties override defaults

-- snaps an object's pixel position to the tile grid
local function snap_tile(v)
  return math.floor(v / TW + 0.5) * TW
end

-- applies an object's extra custom properties onto an entity (per-instance
-- tuning like shoot cooldowns); custom values override entity defaults
local function apply_object_props(e, o)
  for k, v in pairs(o) do
    if k ~= "kind" and k ~= "x" and k ~= "y" and k ~= "g"
    and k ~= "name" and k ~= "type" then e[k] = v end
  end
end

local function scan_spawns(level)
  spawn_points = {}
  -- NOTE: the spawn may remain a marker tile in the tile layer (as in the
  -- current level); everything else is object-based
  for r = 0, MAP_H-1 do
    for c = 0, MAP_W-1 do
      if mget(c, r) == TILE_SPAWN then
        table.insert(spawn_points, {x=c*TW, y=r*TW})
      end
    end
  end
  for _, o in ipairs(level.objects) do
    if o.kind == "spawn" then
      table.insert(spawn_points, {x=o.x, y=o.y})
    end
  end
end

local function scan_enemies(level)
  enemies = {}
  for _, o in ipairs(level.objects) do
    if o.kind == "archer" or o.kind == "melee" then
      local e = {
        x=snap_tile(o.x), y=snap_tile(o.y), vx=0, vy=0, w=6, h=8,
        gr=false, facing=1, type=o.kind, shoot_cd=SHOOT_CD,
        spr=o.spr or ((o.kind == "melee") and TILE_SPR_M or TILE_SPR_A),
        rot=o.rot,
      }
      apply_object_props(e, o)
      table.insert(enemies, e)
    end
  end
end

local function scan_interactables(level)
  keys, locks, doors = {}, {}, {}
  switches, springs = {}, {}
  for _, o in ipairs(level.objects) do
    local k = o.kind
    if k == "key" or k == "lock" or k == "door" or k == "switch"
    or k == "spring" then
      local wx, wy = snap_tile(o.x), snap_tile(o.y)
      if k == "key" then
        table.insert(keys,  {x=wx, y=wy, g=o.g, taken=false,
          spr=o.spr or TILE_KEY, rot=o.rot})
      elseif k == "lock" then
        table.insert(locks, {x=wx, y=wy, g=o.g, triggered=false,
          spr=o.spr or TILE_LOCK, rot=o.rot})
      elseif k == "door" then
        table.insert(doors, {x=wx, y=wy, g=o.g, open=false,
          tc=math.floor(wx/TW), tr=math.floor(wy/TW),
          spr=o.spr or TILE_DOOR, rot=o.rot})
      elseif k == "switch" then
        table.insert(switches, {x=wx, y=wy, g=o.g, on=false,
          spr=o.spr or TILE_SWITCH, rot=o.rot})
      else
        table.insert(springs, {x=wx, y=wy, g=o.g, ext=nil,
          spr=o.spr or TILE_SPRING, rot=o.rot})
      end
    end
  end
end

local spawn_poof  -- forward decl: defined with the particles, used here

-- trigger a lock and open its group's door(s) once every lock of that
-- group is triggered (nil groups match each other: ungrouped = one
-- global puzzle, as before). used by key-carrying arrows and a
-- key-carrying player alike.
local function trigger_lock(l)
  l.triggered = true
  local all_triggered = true
  for _, ol in ipairs(locks) do
    if ol.g == l.g and not ol.triggered then
      all_triggered = false break
    end
  end
  if all_triggered then
    for _, d in ipairs(doors) do
      if not d.open and d.g == l.g then
        d.open = true  -- door tiles left the map at scan; the list draws them
      end
    end
  end
end

-- a switch strike extends every spring in its group for a moment and
-- vaults whoever is standing on one at that instant
local SPRING_VY        = -6    -- launch velocity
local SPRING_EXT_FRAMES = 12   -- extended art duration
local function trigger_springs(g)
  for _, s in ipairs(springs) do
    if s.g == g then
      s.ext = SPRING_EXT_FRAMES
      -- vault the player standing on the spring (feet on its top row)
      if p.gr and math.abs((p.y + p.h) - s.y) <= 2
      and p.x + p.w > s.x and p.x < s.x + TW then
        p.vy = SPRING_VY
        p.gr = false
        p.j_frames = 0
      end
      -- and any enemy standing on it
      for _, e in ipairs(enemies) do
        if e.gr and math.abs((e.y + e.h) - s.y) <= 2
        and e.x + e.w > s.x and e.x < s.x + TW then
          e.vy = SPRING_VY
          e.gr = false
        end
      end
    end
  end
end

local function upd_springs()
  for _, s in ipairs(springs) do
    if s.ext then
      s.ext = s.ext - 1
      if s.ext <= 0 then s.ext = nil end
    end
  end
end

-- switch groups drive their doors dynamically: every switch in the
-- group on -> the group's doors open; any off -> they close again
local function eval_switch_doors(g)
  local all_on = true
  for _, s in ipairs(switches) do
    if s.g == g and not s.on then
      all_on = false break
    end
  end
  for _, d in ipairs(doors) do
    if d.g == g then d.open = all_on end
  end
end

-- a carried key may trigger this lock? grouped items only pair within
-- their group; anything ungrouped (nil) works with anything
local function key_fits_lock(key, l)
  return not key.g or not l.g or key.g == l.g
end

local function player_die()
  -- a carried key drops back into the world where the player fell
  if p.key and not p.key.used then
    spawn_poof(p.x, p.y)
    p.key.taken = false
  end
  respawn()
  arrows, e_arrows = {}, {}
end

-- ===== collision passes =====
local function shielded_by_slope(obj, y)
  local cx = obj.x + obj.w / 2
  local tc = math.floor(cx / TW)
  for tr = math.floor(y/TW)-1, math.floor(y/TW) do
    local st = slope_type[mget(tc, tr)]
    if st and st <= 2 then
      if slope_floor_y(st, tr, cx) <= y + 1 then return true end
    end
  end
  return false
end

local function resolve_x(obj)
  if obj.vx > 0 then
    local rx = obj.x + obj.w - 1
    local hit_top = solid_at(rx, obj.y)
    local hit_bot = solid_at(rx, obj.y+obj.h-1)
    if hit_bot and not hit_top and shielded_by_slope(obj, obj.y+obj.h-1) then
      hit_bot = false
    end
    if hit_top or hit_bot then
      obj.x  = math.floor(rx/TW)*TW - obj.w
      obj.vx = 0
    end
  elseif obj.vx < 0 then
    local hit_top = solid_at(obj.x, obj.y)
    local hit_bot = solid_at(obj.x, obj.y+obj.h-1)
    if hit_bot and not hit_top and shielded_by_slope(obj, obj.y+obj.h-1) then
      hit_bot = false
    end
    if hit_top or hit_bot then
      obj.x  = (math.floor(obj.x/TW)+1)*TW
      obj.vx = 0
    end
  end
end

local function resolve_y(obj)
  if obj.vy >= 0 then
    local by = obj.y + obj.h
    if solid_at(obj.x, by) or solid_at(obj.x+obj.w-1, by) then
      local tc = mget(math.floor(obj.x/TW), math.floor(by/TW))
      obj.y  = math.floor(by/TW)*TW - obj.h
      obj.vy = 0
      obj.gr = true
      obj.fr = tile_friction(tc)
    end
  elseif obj.vy < 0 then
    if solid_at(obj.x, obj.y) or solid_at(obj.x+obj.w-1, obj.y) then
      obj.y  = (math.floor(obj.y/TW)+1)*TW
      obj.vy = 0
    end
  end
end

local function check_walls(obj)
  obj.wall_l, obj.wall_r = false, false
  if obj.gr then return end
  local tr = math.floor(obj.y/TW)
  local br = math.floor((obj.y+obj.h-1)/TW)
  for r = tr, br do
    if tile_solid(mget(math.floor((obj.x-1)/TW), r))   then obj.wall_l = true end
    if tile_solid(mget(math.floor((obj.x+obj.w)/TW), r)) then obj.wall_r = true end
  end
end

-- ===== player physics (30hz) =====
local check_arrow_platforms  -- forward decl (assigned below)

local function upd_player_phys()
  if not btn(4) then
    local ax = 0
    if btn(0) then ax = -1 end
    if btn(1) then ax =  1 end
    if ax ~= 0 then
      p.facing = ax
      local a = p.gr and paccel or (paccel * air)
      p.vx = p.vx + ax * a
    else
      local d = p.gr and (pdecel * p.fr) or (pdecel * 0.35)
      if p.vx > 0 then p.vx = math.max(0, p.vx - d)
      elseif p.vx < 0 then p.vx = math.min(0, p.vx + d) end
    end
    p.vx = math.max(-pspd, math.min(pspd, p.vx))
  else
    local d = p.gr and (pdecel * p.fr) or (pdecel * 0.35)
    if p.vx > 0 then p.vx = math.max(0, p.vx - d)
    elseif p.vx < 0 then p.vx = math.min(0, p.vx + d) end
  end

  if p.jbuf > 0 and p.coy > 0 then
    p.vy       = mv_to(p.vy, jforc, j_iacc)
    p.coy, p.jbuf = 0, 0
    p.j_frames = j_frames_max
  end

  if p.j_frames > 0 then
    if btn(5) and p.vy < 0 then
      p.vy       = mv_to(p.vy, jforc, j_acc)
      p.j_frames = p.j_frames - 1
    else
      if p.vy < 0 then p.vy = p.vy / 2 end
      p.j_frames = 0
    end
  end

  p.vy = p.vy + grav
  p.vy = math.min(p.vy, 3)

  p.x = p.x + p.vx
  resolve_x(p)
  check_walls(p)

  p.gr = false
  p.fr = 1.0
  p.y = p.y + p.vy
  resolve_y(p)
  resolve_slopes(p)
  check_arrow_platforms()

  if p.gr then
    p.coy = coy_t
    p.j_frames = 0
    p.aimed_down = false
    if not p.prev_gr then p.land_frames = 6 end
    if p.land_frames > 0 then p.land_frames = p.land_frames - 1 end
  else
    p.coy = math.max(0, p.coy - 1)
    p.land_frames = 0
  end
  p.prev_gr = p.gr

  -- key interactions: pick a key up from the world, or grab it off any
  -- key-carrying arrow the player touches (flying or stuck); then carry
  -- it to a lock personally
  if not p.key then
    for _, k in ipairs(keys) do
      if not k.taken
      and p.x < k.x+TW and p.x+p.w > k.x
      and p.y < k.y+TW and p.y+p.h > k.y then
        k.taken = true
        p.key   = k
        break
      end
    end
    if not p.key then
      for _, a in ipairs(arrows) do
        if a.active and a.key and not (a.grab_cd and a.grab_cd > 0)
        and a.x >= p.x-1 and a.x <= p.x+p.w+1
        and a.y >= p.y-1 and a.y <= p.y+p.h+1 then
          p.key = a.key
          a.key = nil
          break
        end
      end
    end
  end
  if p.key then
    for _, l in ipairs(locks) do
      if not l.triggered
      and key_fits_lock(p.key, l)
      and p.x < l.x+TW and p.x+p.w > l.x
      and p.y < l.y+TW and p.y+p.h > l.y then
        trigger_lock(l)
        p.key.used = true  -- consumed; not released on death
        p.key      = nil
        break
      end
    end
  end

  -- run cycle: advance at the 30hz sim rate (twang.p8 advanced it in _draw
  -- at 30fps); the port previously ticked it from love.draw at 60fps
  if p.gr and p.vx ~= 0 and not btn(4) then
    run_tick = run_tick + 1
    if run_tick >= 6 then
      run_tick, run_frame = 0, (run_frame + 1) % 4
    end
  else
    run_frame, run_tick = 0, 0
  end

  -- fell off the bottom of the world -> respawn
  if p.y > wh + 32 then player_die() end
end

-- ===== particles =====
local function add_particle(x, y, vx, vy, col, life)
  table.insert(particles, {x=x, y=y, vx=vx, vy=vy, col=col, life=life})
end

function spawn_poof(x, y)  -- assigns the forward-declared local above
  for _ = 1, 8 do
    local a   = math.random() * math.pi * 2
    local spd = math.random() * 1.5 + 0.5
    add_particle(x, y, math.cos(a)*spd, math.sin(a)*spd, 10, math.random(8, 15))
  end
end

local function spawn_blood(x, y, avx, avy)
  local len = math.sqrt(avx*avx+avy*avy)
  if len == 0 then len = 1 end
  local base = math.atan2(-avy/len, -avx/len)
  for _ = 1, BLOOD_N do
    local a   = base + math.random()*0.25 - 0.125
    local spd = math.random()*1.5 + 0.5
    add_particle(x, y, math.cos(a)*spd, math.sin(a)*spd, 8, math.random(10, 19))
  end
end

local function upd_particles()
  for i = #particles, 1, -1 do
    local pt = particles[i]
    pt.x = pt.x + pt.vx
    pt.y = pt.y + pt.vy
    pt.vy = pt.vy + 0.06
    pt.life = pt.life - 1
    if pt.life <= 0 then table.remove(particles, i) end
  end
end

-- releases a carried key back into the world (with a poof, as in twang.p8)
local function release_key(a)
  if a.key and not a.key.used then
    spawn_poof(a.x, a.y)
    a.key.taken = false
  end
  a.key = nil
end

local function do_fire_at(angle)
  if #arrows >= max_arr then
    -- evict a stuck arrow to make room (release its key first, if any)
    for i, a in ipairs(arrows) do
      if a.stuck then
        release_key(a)
        table.remove(arrows, i)
        break
      end
    end
    if #arrows >= max_arr then return end
  end
  local dx = p8cos(angle)
  local dy = p8sin(angle)
  local spd = arrow_spds[p.aim_power]
  local arrow = {
    x=p.x+pw/2, y=p.y+ph/2,
    vx=dx*spd, vy=dy*spd,
    active=true, stuck=false, bounced=0,
    sdx=dx, sdy=dy, spin=0, lt=300,
  }
  -- a fired arrow takes the player's carried key along; the player can
  -- grab it back on contact once the short cooldown lapses (the arrow
  -- spawns inside the player, so without it the handoff would undo
  -- itself the same step)
  if p.key then
    arrow.key     = p.key
    arrow.grab_cd = 8
    p.key = nil
  end
  table.insert(arrows, arrow)
end
function check_arrow_platforms()
  if p.vy < 0 then return end
  for _, a in ipairs(arrows) do
    if a.stuck and a.active and not a.on_slope
    and math.abs(a.sdx) >= math.abs(a.sdy) then
      -- only arrows embedded in vertical walls (horizontal travel) act
      -- as platforms; the wall face was recorded at stick time (the
      -- retracted tip no longer sits inside the wall tile)
      local ay = a.y
      local by = p.y + p.h
      if by >= ay - 1 and by <= ay + 4 then
        local ax1, ax2
        local wx = a.face
        if not wx then
          wx = a.sdx > 0 and math.floor(a.x/TW)*TW
                        or (math.floor(a.x/TW)+1)*TW
        end
        if a.sdx > 0 then
          ax1, ax2 = wx - 7, wx + 2
        else
          ax1, ax2 = wx - 2, wx + 7
        end
        if p.x + p.w > ax1 and p.x < ax2 then
          p.y  = ay - p.h
          p.vy = 0
          p.gr = true
          p.coy = coy_t
        end
      end
    end
  end
end

-- ===== enemies =====
local function upd_enemy(e)
  e.vy = math.min(e.vy + grav, 3)
  e.gr = false
  e.y  = e.y + e.vy
  resolve_y(e)
  resolve_slopes(e)

  if e.gr then
    local spd = (e.type == "melee") and MELEE_SPD or ARCHER_SPD
    local px = e.facing > 0 and (e.x+e.w) or (e.x-1)
    local wall_ahead  = solid_at(px, e.y+e.h/2)
    local ledge_ahead = not solid_at(px, e.y+e.h)
    if wall_ahead or ledge_ahead then e.facing = -e.facing end
    e.vx = spd * e.facing
  else
    e.vx = e.vx * 0.85
  end

  e.x = e.x + e.vx
  resolve_x(e)

  if e.x < 0 then e.x = 0 e.facing = 1 end
  if e.x+e.w > ww then e.x = ww-e.w e.facing = -1 end

  if e.type == "melee" and aabb(e, p) then
    player_die()
    return
  end

  if e.type == "archer" then
    if e.shoot_cd > 0 then e.shoot_cd = e.shoot_cd - 1 end
    if math.abs(p.x - e.x) < DETECT_DIST and e.shoot_cd == 0 then
      local ex, ey = e.x+e.w/2, e.y+e.h/2
      local tx, ty = p.x+pw/2,  p.y+ph/2
      local ddx, ddy = tx-ex, ty-ey
      local len = math.sqrt(ddx*ddx+ddy*ddy)
      if len > 0 then
        table.insert(e_arrows, {
          x=ex, y=ey,
          vx=ddx/len*arrow_cfg.spd,
          vy=ddy/len*arrow_cfg.spd,
          active=true,
        })
      end
      e.shoot_cd = SHOOT_CD
    end
  end
end

-- FIXED in port: only enemies near the camera are simulated
local function update_enemies()
  local m, M = 320, VW + 320
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    if e.x >= cam.x - m and e.x <= cam.x + M
    and e.y >= cam.y - 256 and e.y <= cam.y + VH + 256 then
      upd_enemy(e)
    end
  end
end

local function upd_e_arrows()
  for i = #e_arrows, 1, -1 do
    local a = e_arrows[i]
    if not a then break end  -- e_arrows was reset mid-loop (player died)
    if not a.active then
      table.remove(e_arrows, i)
    else
      a.vy = a.vy + arrow_cfg.grv
      local nx = a.x + a.vx
      local ny = a.y + a.vy
      if solid_for_arrow(nx, ny) or in_slope_solid(nx, ny) then
        a.active = false
      else
        a.x, a.y = nx, ny
        if nx >= p.x and nx < p.x+pw and ny >= p.y and ny < p.y+ph then
          player_die()
          a.active = false
        end
        if a.y < -10 or a.x < -10 or a.x > ww or a.y > wh then
          a.active = false
        end
      end
    end
  end
end

-- ===== player arrows =====
local function upd_arrow(a)
  if a.grab_cd and a.grab_cd > 0 then a.grab_cd = a.grab_cd - 1 end
  a.lt = a.lt - 1
  if a.lt <= 0 then a.active = false return end
  if a.stuck then return end

  -- out of bounces: keep flying and spinning briefly, then poof
  if a.dying then
    a.dying = a.dying - 1
    a.spin  = a.spin + DIE_SPIN
    local nx, ny = a.x + a.vx, a.y + a.vy
    if a.dying <= 0 or solid_at(nx, ny) or in_slope_solid(nx, ny) then
      spawn_poof(a.x, a.y)
      a.active = false
      return
    end
    a.x, a.y = nx, ny
    return
  end

  a.vy = a.vy + arrow_cfg.grv
  -- substep the flight so fast arrows never skip a tile: collision and
  -- tip interactions are sampled every ~4px along the frame's path
  local nsub = math.max(1, math.ceil((math.abs(a.vx) + math.abs(a.vy)) / 4))
  local sx, sy = a.vx / nsub, a.vy / nsub
  for _ = 1, nsub do
    local nx = a.x + sx
    local ny = a.y + sy

    if in_slope_solid(nx, ny) then
      local spd = math.sqrt(a.vx*a.vx + a.vy*a.vy)
      a.sdx = spd > 0 and (a.vx/spd) or a.sdx
      a.sdy = spd > 0 and (a.vy/spd) or a.sdy
      a.x, a.y = nx, ny
      a.stuck, a.on_slope = true, true
      a.lt = 32000
      return
    end

    if solid_for_arrow(nx, ny) then
      local hx = solid_for_arrow(nx, a.y)
      local hy = solid_for_arrow(a.x, ny)
      local is_sticky = (hx and sticky_at(nx, a.y))
                     or (hy and sticky_at(a.x, ny))
                     or (not hx and not hy and sticky_at(nx, ny))
      if is_sticky then
        -- bounce: reflect velocity off the hit surface, conserving speed
        if hx then a.vx = -a.vx end
        if hy then a.vy = -a.vy end
        if not hx and not hy then a.vx, a.vy = -a.vx, -a.vy end
        a.bounced = a.bounced + 1
        if a.bounced > BOUNCE_MAX then
          a.dying = DIE_FRAMES
          a.spin  = 0
        end
      else
        local spd = math.sqrt(a.vx*a.vx + a.vy*a.vy)
        a.sdx = spd > 0 and (a.vx/spd) or a.sdx
        a.sdy = spd > 0 and (a.vy/spd) or a.sdy
        a.stuck = true
        a.lt = 32000
        if hx then
          -- stick with the tip AT the wall face, pulled a little further
          -- out, so the shaft and a carried key stay in the player's reach
          a.face = a.vx > 0 and math.floor(nx / TW) * TW
                           or (math.floor(nx / TW) + 1) * TW
          a.x = a.face - (a.vx > 0 and 3 or -3)
        else
          a.x = nx
        end
        if hy then
          a.y = (a.vy > 0) and (math.floor(ny / TW) * TW)
                            or ((math.floor(ny / TW) + 1) * TW)
        else
          a.y = ny
        end
        if not hx and a.key and not a.key.used then
          -- floor/ceiling hit: the key poofs back into the world
          spawn_poof(a.x, a.y)
          a.key.taken = false
          a.key = nil
        end
      end
      return
    end

    a.x, a.y = nx, ny

  -- key pickup by arrow tip
  if not a.key then
    for _, k in ipairs(keys) do
      if not k.taken
      and nx >= k.x and nx < k.x+TW
      and ny >= k.y and ny < k.y+TW then
        a.key, k.taken = k, true
        break
      end
    end
  end

  -- arrow strikes a switch: toggle it and re-evaluate its group's doors
  -- (one toggle per pass through a switch's tile)
  local in_switch = false
  for _, s in ipairs(switches) do
    if nx >= s.x and nx < s.x+TW and ny >= s.y and ny < s.y+TW then
      in_switch = true
      if a.last_switch ~= s then
        a.last_switch = s
        if not s.on then
          -- latching: one strike activates a switch permanently
          s.on = true
          eval_switch_doors(s.g)
          trigger_springs(s.g)
        end
      end
    end
  end
  if not in_switch then a.last_switch = nil end

  -- key-carrying arrow passes through a lock
  if a.key then
    for _, l in ipairs(locks) do
      if not l.triggered
      and key_fits_lock(a.key, l)
      and nx >= l.x and nx < l.x+TW
      and ny >= l.y and ny < l.y+TW then
        trigger_lock(l)
        a.key.used = true  -- consumed; will not respawn if arrow expires
        a.key      = nil
        break
      end
    end
  end

  -- enemy hit
  for i, e in ipairs(enemies) do
    if nx >= e.x and nx < e.x+e.w and ny >= e.y and ny < e.y+e.h then
      spawn_blood(nx, ny, a.vx, a.vy)
      table.remove(enemies, i)
      a.active = false
      return
    end
  end

    if a.y < -10 or a.x < -10 or a.x > ww or a.y > wh then
      a.active = false
      return
    end
  end
end

local function upd_arrows()
  for i = #arrows, 1, -1 do
    local a = arrows[i]
    if not a then break end  -- arrows was reset mid-loop (player died)
    if not a.active then
      release_key(a)  -- poof the key back into the world if never consumed
      table.remove(arrows, i)
    else
      upd_arrow(a)
    end
  end
end

-- ===== camera: smooth follow, clamped to world =====
local function upd_cam()
  local tx = p.x + p.w/2 - VW/2
  local ty = p.y + p.h/2 - VH/2
  tx = math.max(0, math.min(ww - VW, tx))
  ty = math.max(0, math.min(wh - VH, ty))
  cam.x = cam.x + (tx - cam.x) * 0.15
  cam.y = cam.y + (ty - cam.y) * 0.15
end

-- one 30hz tick (mirrors _update in twang.p8)
local function step()
  slow_cnt = slow_cnt + 1
  tick_held()

  if btn(4) then
    if not p.was_aiming then
      -- first frame of aim mode: aim along the stick if pushed, else
      -- face straight ahead
      local sx, sy = aim_stick_vec()
      if sx then
        p.aim_angle = (math.atan2(sy, sx) / TAU) % 1
      else
        p.aim_angle = p.facing > 0 and 0 or 0.5
      end
      p.aim_power  = 2
      p.was_aiming = true
      p.aimed_down = false
    end
    -- analog aiming: the stick owns the angle; dpad/arrow left/right
    -- only nudges when the stick is idle
    local sx, sy = aim_stick_vec()
    if sx then
      p.aim_angle = (math.atan2(sy, sx) / TAU) % 1
    elseif btn(0) then
      p.aim_angle = (p.aim_angle + 0.007) % 1
    elseif btn(1) then
      p.aim_angle = (p.aim_angle - 0.007) % 1
    end
    -- power levels: keyboard up/down or the physical dpad (held[2]/[3]
    -- deliberately exclude the analog stick)
    if btnp(2) then p.aim_power = math.min(3, p.aim_power + 1) end
    if btnp(3) then p.aim_power = math.max(1, p.aim_power - 1) end
  else
    if p.was_aiming then
      if p8sin(p.aim_angle) > 0.5 then p.aimed_down = true end
      do_fire_at(p.aim_angle)
      p.was_aiming = false
    end
    if btnp(5) then p.jbuf = jbuf_t end
  end
  if p.jbuf > 0 then p.jbuf = p.jbuf - 1 end

  local do_phys = not btn(4) or (slow_cnt % SLOW_N == 0)
  if do_phys then
    upd_player_phys()
    upd_arrows()
    update_enemies()
    upd_e_arrows()
    upd_particles()
    upd_springs()
    upd_cam()
  end
end

-- one 30hz tick of the controls panel (game world is paused). kept for
-- future settings; right now it only closes.
local function menu_step()
  tick_held()
  -- future settings (control tweaks, toggles) go here
  if btnp(4) or btnp(5) then
    menu_open = false
  end
end

-- ===== drawing =====
local canvas, sheet, quads = nil, nil, {}

local function get_quad(s)
  if not quads[s] then
    quads[s] = love.graphics.newQuad(
      (s % 16) * 8, math.floor(s / 16) * 8, 8, 8,
      sheet:getWidth(), sheet:getHeight())
  end
  return quads[s]
end

local function pspr(s, x, y, flip, rot)
  local q = get_quad(s)
  love.graphics.setColor(1, 1, 1, 1)
  if rot then
    -- rotated: pivot the sprite's corner so it still fills its cell
    local rad = math.rad(rot)
    local ox, oy = 0, 0
    if rot == 90 then ox, oy = 8, 0
    elseif rot == 180 then ox, oy = 8, 8
    elseif rot == 270 then ox, oy = 0, 8 end
    love.graphics.draw(sheet, q, x + ox, y + oy, rad)
  elseif flip then
    love.graphics.draw(sheet, q, x + 8, y, 0, -1, 1)
  else
    love.graphics.draw(sheet, q, x, y)
  end
end

local function draw_map()
  local mx = math.floor(cam.x / TW)
  local my = math.floor(cam.y / TW)
  love.graphics.setColor(1, 1, 1, 1)
  for r = my, my + VH/TW do
    for c = mx, mx + VW/TW + 1 do
      local t = mget(c, r)
      if t ~= 0 then
        love.graphics.draw(sheet, get_quad(t), c*TW, r*TW)
      end
    end
  end
end

local function draw_interactables()
  for _, k in ipairs(keys) do
    if not k.taken then pspr(k.spr or TILE_KEY, k.x, k.y, false, k.rot) end
  end
  for _, l in ipairs(locks) do
    if not l.triggered then pspr(l.spr or TILE_LOCK, l.x, l.y, false, l.rot) end
  end
  for _, d in ipairs(doors) do
    if not d.open then pspr(d.spr or TILE_DOOR, d.x, d.y, false, d.rot) end
  end
  for _, s in ipairs(switches) do
    pspr(s.on and (s.spr + 1) or s.spr, s.x, s.y, false, s.rot)
  end
  for _, s in ipairs(springs) do
    pspr(s.ext and TILE_SPRING_EXT or (s.spr or TILE_SPRING),
      s.x, s.y, false, s.rot)
  end
end

local function draw_player()
  local s
  if not p.gr then
    s = 97
  elseif p.vx ~= 0 and not btn(4) then
    s = 100 + run_frame
  else
    s = 96
  end
  if p.land_frames > 0 then s = 99
  elseif btn(4) and p8sin(p.aim_angle) > 0.5 then s = 98
  elseif p.aimed_down and not p.gr then s = 98
  end

  local draw_facing = p.facing
  if btn(4) then
    local ax = p8cos(p.aim_angle)
    if ax > 0 then draw_facing = 1
    elseif ax < 0 then draw_facing = -1 end
  end
  pspr(s, p.x - 2, p.y - 2, draw_facing < 0)
  -- a carried key rides centred on the player
  if p.key then
    pspr(TILE_KEY, p.x - 2, p.y - 1)
  end

  -- aim indicator + predicted trajectory
  if btn(4) then
    local cx, cy = p.x + pw/2, p.y + ph/2
    local spd = arrow_spds[p.aim_power]
    if p8sin(p.aim_angle) <= 0.5 then
      local ex = cx + p8cos(p.aim_angle) * 8
      local ey = cy + p8sin(p.aim_angle) * 8
      love.graphics.setColor(pcol(10))
      love.graphics.line(cx, cy, ex, ey)
    end
    local tvx  = p8cos(p.aim_angle) * spd
    local tvy  = p8sin(p.aim_angle) * spd
    local tx, ty = cx, cy
    love.graphics.setColor(pcol(arrow_cfg.col))
    -- bounce-aware preview: reflects off sticky surfaces exactly like a
    -- flying arrow, and stops where the arrow would stick. dots every
    -- step, 14 steps: a shorter, tighter line now that arrows fly faster
    for i = 1, 14 do
      tvy = tvy + arrow_cfg.grv
      local nx, ny = tx + tvx, ty + tvy
      if solid_for_arrow(nx, ny) then
        local hx = solid_for_arrow(nx, ty)
        local hy = solid_for_arrow(tx, ny)
        local sticky = (hx and sticky_at(nx, ty))
                    or (hy and sticky_at(tx, ny))
                    or (not hx and not hy and sticky_at(nx, ny))
        if sticky then
          if hx then tvx = -tvx end
          if hy then tvy = -tvy end
          if not hx and not hy then tvx, tvy = -tvx, -tvy end
        else
          love.graphics.points(nx, ny)  -- the arrow sticks here
          break
        end
      end
      tx, ty = nx, ny
      love.graphics.points(tx, ty)
    end
  end
end

local function draw_arrows()
  for _, a in ipairs(arrows) do
    if a.active then
      if a.stuck then
        love.graphics.setColor(pcol(7))
        love.graphics.points(a.x, a.y)
        love.graphics.setColor(pcol(arrow_cfg.col))
        love.graphics.line(a.x, a.y, a.x - a.sdx*4, a.y - a.sdy*4)
      elseif a.dying then
        -- spin-out: shaft whirling around its centre, tip leading
        local ca = math.cos(a.spin)
        local sa = math.sin(a.spin)
        love.graphics.setColor(pcol(arrow_cfg.col))
        love.graphics.line(a.x - ca*2, a.y - sa*2, a.x + ca*2, a.y + sa*2)
        love.graphics.setColor(pcol(7))
        love.graphics.points(a.x + ca*2, a.y + sa*2)
      else
        local len = math.sqrt(a.vx*a.vx + a.vy*a.vy)
        if len > 0 then
          love.graphics.setColor(pcol(arrow_cfg.col))
          love.graphics.line(a.x, a.y,
            a.x - (a.vx/len)*3, a.y - (a.vy/len)*3)
          love.graphics.setColor(pcol(7))
          love.graphics.points(a.x, a.y)
        end
      end
      if a.key then pspr(TILE_KEY, a.x - 4, a.y - 4) end
    end
  end
end

local function draw_enemies()
  for _, e in ipairs(enemies) do
    pspr(e.spr or ((e.type == "melee") and TILE_SPR_M or TILE_SPR_A),
      e.x, e.y, e.facing < 0, e.rot)
  end
end

local function draw_e_arrows()
  for _, a in ipairs(e_arrows) do
    if a.active then
      local len = math.sqrt(a.vx*a.vx + a.vy*a.vy)
      if len > 0 then
        love.graphics.setColor(pcol(8))
        love.graphics.line(a.x, a.y, a.x - (a.vx/len)*3, a.y - (a.vy/len)*3)
        love.graphics.setColor(pcol(7))
        love.graphics.points(a.x, a.y)
      end
    end
  end
end

local function draw_particles()
  for _, pt in ipairs(particles) do
    love.graphics.setColor(pcol(pt.col or 8))
    love.graphics.points(pt.x, pt.y)
  end
end

local function draw_world()
  draw_map()
  draw_interactables()
  draw_particles()
  draw_enemies()
  draw_e_arrows()
  draw_arrows()
  draw_player()
end

-- HUD drawn at window scale, anchored to the blitted canvas rect so text
-- stays readable and aligned even when the window is resized
local blit = {scale = 1, ox = 0, oy = 0}

local function draw_hud()
  love.graphics.push()
  love.graphics.translate(blit.ox, blit.oy)
  love.graphics.scale(blit.scale)
  if btn(4) then
    local pwr_col = {[1]=12, [2]=10, [3]=8}
    love.graphics.setColor(pcol(pwr_col[p.aim_power]))
    love.graphics.print("pwr:" .. ({"lo","md","hi"})[p.aim_power], VW - 40, 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("z:aim  lr:ang  ud:pwr", 2, VH - 12)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("x:jump  z:bow", 2, VH - 12)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

-- controls panel overlay (drawn on the 240x160 canvas, pixelated)
local function draw_menu()
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 30, 34, 180, 74)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", 30.5, 34.5, 179, 73)

  love.graphics.setColor(pcol(10))
  love.graphics.print("controls", 98, 40)

  love.graphics.setColor(pcol(7))
  love.graphics.print("stick/dpad/arrows: move", 52, 56)
  love.graphics.print("hold aim + stick: aim the bow", 52, 64)
  love.graphics.print("power: ud / dpad ud", 52, 72)
  love.graphics.print("jump: x / A / B     aim: z / RB / RT", 52, 80)

  love.graphics.setColor(pcol(12))
  love.graphics.print("m / start: panel      x: back", 52, 94)
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(pcol(15))
  love.graphics.push()
  love.graphics.translate(-math.floor(cam.x), -math.floor(cam.y))
  draw_world()
  love.graphics.pop()
  if menu_open then draw_menu() end
  love.graphics.setCanvas()

  -- blit 240x160 canvas to the window, preserving aspect
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setScissor()
  local sw, sh = love.graphics.getDimensions()
  local scale  = math.min(sw / VW, sh / VH)
  local ox     = (sw - VW * scale) / 2
  local oy     = (sh - VH * scale) / 2
  love.graphics.draw(canvas, ox, oy, 0, scale)
  blit.scale, blit.ox, blit.oy = scale, ox, oy

  draw_hud()
end

-- ===== love callbacks =====
function love.load()
  math.randomseed(os.time())
  sheet = love.graphics.newImage("spritesheet.png")
  sheet:setFilter("nearest", "nearest")
  canvas = love.graphics.newCanvas(VW, VH)
  canvas:setFilter("nearest", "nearest")

  -- level: Tiled JSON map (flags/kinds/slopes come from tileset properties)
  local level = tiled.load(MAP_FILE)
  MAP_W, MAP_H = level.MAP_W, level.MAP_H
  ww, wh       = MAP_W * TW, MAP_H * TW
  gff          = level.gff
  map          = level.map
  for k in pairs(slope_type) do slope_type[k] = nil end
  for k, v in pairs(level.slope_type) do slope_type[k] = v end
  TILE_KEY    = level.special.key    or 70
  TILE_LOCK   = level.special.lock   or 71
  TILE_DOOR   = level.special.door   or 72
  TILE_SWITCH = level.special.switch or 171
  TILE_SPRING    = level.special.spring    or 16
  TILE_SPRING_EXT = level.special.spring_ext or 33
  TILE_SPR_A  = level.special.archer or 90
  TILE_SPR_M  = level.special.melee  or 105

  arrows, enemies, e_arrows, particles = {}, {}, {}, {}
  keys, locks, doors, spawn_points = {}, {}, {}, {}
  switches, springs = {}, {}
  cam = {x = 0, y = 0}

  scan_spawns(level)
  scan_enemies(level)
  scan_interactables(level)
  respawn()  -- snaps the camera onto the spawn point, clamped
end

local acc, STEP = 0, 1/30

function love.update(dt)
  refresh_held()
  -- clamp dt so tab-through / slow frames never produce a huge catchup
  acc = math.min(acc + dt, 0.25)
  while acc >= STEP do
    acc = acc - STEP
    if menu_open then menu_step() else step() end
  end
end

function love.draw()
  draw()
end

function love.keypressed(k, sc, isrepeat)
  if k == "escape" then love.event.quit() return end
  local i = keymap[k]
  -- latch presses immediately so sub-frame taps are never lost; OS key
  -- repeats are ignored (the 30hz tick_held provides pico-8-style repeat)
  if i and not isrepeat then press_latch[i] = true end
  -- m / tab toggle the control-style menu (start does it on gamepads)
  if not isrepeat and (k == "m" or k == "tab") then
    menu_open = not menu_open
  end
end

function love.focus(f)
  if not f then
    -- window lost focus: drop all input so no key stays stuck
    for i = 0, 5 do
      held[i], hold_cnt[i] = false, 0
      press_latch[i], press_edge[i] = false, false
    end
  end
end

function love.gamepadpressed(pad, button)
  if button == "start" then  -- start toggles the control-style menu
    menu_open = not menu_open
    return
  end
  if button == "back" then love.event.quit() return end
  local i = gpmap[button]
  if i then press_latch[i] = true end
end

-- ===== appended test hook =====
-- This file is a FROZEN copy of main.lua as of commit de8dd0a ("Various
-- fixes"), kept as the reference oracle for the refactor. The only change
-- is this appended block, which registers a state snapshot function under
-- the headless harness (tests/run.lua). It is inert in a real LÖVE run.
if TWANG_TEST then
  local function trace_arrow(a)
    return {
      x=a.x, y=a.y, vx=a.vx, vy=a.vy, active=a.active, stuck=a.stuck,
      bounced=a.bounced, dying=a.dying, spin=a.spin, lt=a.lt,
      grab_cd=a.grab_cd, sdx=a.sdx, sdy=a.sdy, face=a.face,
      on_slope=a.on_slope,
      key=a.key and (a.key.g or "ungrouped") or false,
    }
  end
  TWANG_TEST.trace = function(step)
    local arr, earr, ene = {}, {}, {}
    for _, a in ipairs(arrows) do arr[#arr+1] = trace_arrow(a) end
    for _, a in ipairs(e_arrows) do
      earr[#earr+1] = {x=a.x, y=a.y, vx=a.vx, vy=a.vy, active=a.active}
    end
    for _, e in ipairs(enemies) do
      ene[#ene+1] = {x=e.x, y=e.y, vx=e.vx, vy=e.vy, gr=e.gr,
        facing=e.facing, type=e.type, shoot_cd=e.shoot_cd}
    end
    local ks, ls, ds, sws, sps = {}, {}, {}, {}, {}
    for _, k in ipairs(keys) do ks[#ks+1] = {taken=k.taken, g=k.g} end
    for _, l in ipairs(locks) do ls[#ls+1] = {triggered=l.triggered, g=l.g} end
    for _, d in ipairs(doors) do ds[#ds+1] = {open=d.open, g=d.g} end
    for _, s in ipairs(switches) do sws[#sws+1] = {on=s.on, g=s.g} end
    for _, s in ipairs(springs) do sps[#sps+1] = {ext=s.ext, g=s.g} end
    return {
      step = step,
      player = {
        x=p.x, y=p.y, vx=p.vx, vy=p.vy, w=p.w, h=p.h, gr=p.gr,
        facing=p.facing, coy=p.coy, jbuf=p.jbuf, fr=p.fr,
        j_frames=p.j_frames, aim_angle=p.aim_angle, aim_power=p.aim_power,
        was_aiming=p.was_aiming, aimed_down=p.aimed_down,
        prev_gr=p.prev_gr, land_frames=p.land_frames,
        key=p.key and (p.key.g or "ungrouped") or false,
      },
      cam = {x=cam.x, y=cam.y},
      arrows = arr,
      e_arrows = earr,
      enemies = ene,
      keys = ks, locks = ls, doors = ds, switches = sws, springs = sps,
      particles = #particles,
      run_frame = run_frame, run_tick = run_tick,
    }
  end
end
