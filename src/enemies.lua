-- Enemies: patrolling melee contact-killers and archers with a
-- sense -> aim -> volley -> investigate brain. Patrols are bounded: an
-- enemy turns back at walls, ledges, or enemies.roam_tiles from its
-- spawn point.
--
-- Archer senses:
--   * the player must be inside `detect_distance`, in front of the archer
--     (its back is turned otherwise) and in clear line of sight (terrain
--     blocks vision)
--   * spotting the player starts an aim: the archer stops, solves a
--     ballistic arc to the player (flat arc first, lob if blocked) and
--     shows the arc, exactly like the player's aim preview
--   * after `aim_steps` it fires a spread volley of `volley_count`
--     arrows, released one at a time a few steps apart
--   * while the player stays visible it keeps shooting on a quick, semi
--     randomized cadence (`rapid_min`..`rapid_min`+`rapid_extra` steps
--     between volleys), until it loses the player
--   * if the player is no longer visible while aiming or between
--     volleys, the volley fires anyway at the last solved arc and the
--     archer investigates the last known position -- walking off ledges
--     if it must (drops deeper than `max_drop_tiles` are refused and
--     end the search); the search times out or ends on arrival
--   * on a small platform with a wall within two tiles behind, an
--     archer holds the edge instead of pacing back and forth
--
-- Only enemies near the camera are simulated (a port fix over the cart,
-- which simulated everything).

local config = require("src.config")
local Util = require("src.util")
local Arrows = require("src.arrows")

local Enemies = {}

-- ==== archer senses ====

-- True when the player is in range, in front of the archer (its back is
-- turned otherwise) and visible: nothing solid along the eye -> player
-- ray. Exposed for tests.
function Enemies.sees(ctx, e)
  local cfg = config.enemies
  local p = ctx.player
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local tx, ty = p.x + p.w/2, p.y + p.h/2
  local dx, dy = tx - ex, ty - ey
  -- its back is turned: the player must be in the facing half-plane
  if dx * e.facing <= 0 then return false end
  local dist2 = dx*dx + dy*dy
  if dist2 > cfg.detect_distance * cfg.detect_distance then return false end
  local dist = math.sqrt(dist2)
  if dist == 0 then return true end
  local ux, uy = dx/dist, dy/dist
  local world = ctx.world
  local step = cfg.sight_step
  for d = step, dist - 1, step do
    local x, y = ex + ux*d, ey + uy*d
    if world:solid_at(x, y) or world:in_slope_solid(x, y) then
      return false
    end
  end
  return true
end

-- Solves the ballistic arc from origin to target for an arrow flying at
-- `speed` under `gravity` (positive downward). `high` picks the loftier
-- arc; returns vx, vy or nil when no arc reaches the target.
local function ballistic(dx, dy, speed, gravity, high)
  local a = gravity * gravity / 4
  local b = -(gravity * dy + speed * speed)
  local c = dx*dx + dy*dy
  local disc = b*b - 4*a*c
  if a == 0 or disc < 0 then return nil end
  local root = math.sqrt(disc)
  local u = high and ((-b + root) / (2*a)) or ((-b - root) / (2*a))
  if u <= 0 then return nil end
  local t = math.sqrt(u)
  return dx / t, (dy - gravity * u / 2) / t
end

-- Aims at (tx, ty): prefers a flat arc that reaches the target without
-- hitting terrain, then a lobbed arc over the obstacle, then falls back
-- to aiming straight at the target. Stores the solution on the archer.
local function solve_aim(ctx, e, tx, ty)
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local speed = config.arrows.enemy_speed
  local gravity = config.arrows.gravity
  local dx, dy = tx - ex, ty - ey
  for _, high in ipairs({false, true}) do
    local vx, vy = ballistic(dx, dy, speed, gravity, high)
    if vx then
      local path = Arrows.simulate_path(ctx.world, ex, ey, vx, vy, {
        target = {x = tx, y = ty},
        max_frames = 120,
      })
      if path.reached then
        e.aim_vx, e.aim_vy = vx, vy
        e.aim_tx, e.aim_ty = tx, ty
        e.aim_blocked = false
        return
      end
    end
  end
  -- nothing clear: fall back to aiming straight at the target
  local len = math.sqrt(dx*dx + dy*dy)
  if len > 0 then
    e.aim_vx, e.aim_vy = dx/len*speed, dy/len*speed
  else
    e.aim_vx, e.aim_vy = speed * e.facing, 0
  end
  e.aim_tx, e.aim_ty = tx, ty
  e.aim_blocked = true
end

-- ==== archer brain ====

local function enter_aim(ctx, e)
  local cfg = config.enemies
  local p = ctx.player
  e.state = "aim"
  e.aim_t = cfg.aim_steps
  e.last_known = {x = p.x + p.w/2, y = p.y + p.h/2}
  solve_aim(ctx, e, e.last_known.x, e.last_known.y)
end

-- Spawns one enemy arrow flying at `angle` (radians) from (x, y).
function Enemies.spawn_e_arrow(ctx, x, y, angle)
  local speed = config.arrows.enemy_speed
  table.insert(ctx.ents.e_arrows, {
    x = x, y = y,
    vx = math.cos(angle) * speed,
    vy = math.sin(angle) * speed,
    active = true,
  })
end

-- Queues a spread volley along the aimed direction: the first arrow
-- leaves immediately, the rest follow one at a time, staggered a few
-- steps apart (like quick successive shots).
function Enemies.fire_volley(ctx, e)
  local cfg = config.enemies
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local base
  if e.aim_vx then
    base = math.atan2(e.aim_vy, e.aim_vx)
  else
    base = e.facing > 0 and 0 or math.pi
  end
  local n = cfg.volley_count
  e.volley = {}
  for i = 0, n - 1 do
    local angle = base + (i - (n - 1)/2) * cfg.volley_spread
    if i == 0 then
      Enemies.spawn_e_arrow(ctx, ex, ey, angle)
    else
      e.volley[#e.volley + 1] = { t = i * cfg.volley_stagger, angle = angle }
    end
  end
  e.shoot_cd = config.enemies.shoot_cooldown
end

-- One 30hz tick of the archer brain: spotting, aiming, volleying,
-- rapid-fire cadence while the player stays visible, and investigating
-- the last known player position.
local function archer_brain(ctx, e)
  local cfg = config.enemies
  local seen = Enemies.sees(ctx, e)

  if e.state == "aim" then
    if seen then
      local p = ctx.player
      e.last_known = {x = p.x + p.w/2, y = p.y + p.h/2}
      solve_aim(ctx, e, e.last_known.x, e.last_known.y)
      e.facing = e.aim_vx > 0 and 1 or -1  -- face the aim
      if not e.aim_blocked then
        e.aim_t = e.aim_t - 1  -- blocked arcs hold the shot in place
      end
    else
      e.aim_t = e.aim_t - 1
    end
    if e.aim_t <= 0 then
      Enemies.fire_volley(ctx, e)
      e.aim_vx, e.aim_vy = nil, nil
      if seen then
        -- still has the player: quick, slightly randomized follow-ups
        e.state = "wait"
        e.wait_t = cfg.rapid_min + math.random(0, cfg.rapid_extra)
      else
        -- the player slipped away mid-aim: fire anyway, then search
        e.state = "investigate"
        e.investigate_t = cfg.investigate_timeout
      end
    end
  elseif e.state == "wait" then
    if seen then
      local p = ctx.player
      e.facing = (p.x + p.w/2 >= e.x + e.w/2) and 1 or -1
      e.wait_t = e.wait_t - 1
      if e.wait_t <= 0 then enter_aim(ctx, e) end
    else
      -- lost the player between volleys: go look for it
      e.state = "investigate"
      e.investigate_t = cfg.investigate_timeout
    end
  elseif e.state == "investigate" then
    e.investigate_t = e.investigate_t - 1
    if seen and e.shoot_cd == 0 then
      enter_aim(ctx, e)
    elseif e.investigate_t <= 0
    or math.abs(e.x + e.w/2 - e.last_known.x) <= cfg.investigate_reach then
      e.state = "patrol"
    end
  else
    if seen and e.shoot_cd == 0 then
      enter_aim(ctx, e)
    end
  end
end

-- ==== shared movement ====

-- Patrol walk: turn around at walls, ledges and the roam limit (an
-- enemy never patrols more than enemies.roam_tiles from its spawn
-- point, so it cannot wander off along flat ground).
local function patrol(e, spd, world)
  local px = e.facing > 0 and (e.x+e.w) or (e.x-1)
  local wall_ahead  = world:solid_at(px, e.y+e.h/2)
  local ledge_ahead = not world:solid_at(px, e.y+e.h)
  local roam = config.enemies.roam_tiles * config.tile_size
  local beyond_roam = e.home_x ~= nil
    and ((e.facing > 0 and e.x + e.w >= e.home_x + roam)
      or (e.facing < 0 and e.x <= e.home_x - roam))
  if wall_ahead or ledge_ahead or beyond_roam then e.facing = -e.facing end
  e.vx = spd * e.facing
end

-- A small backed perch: a wall within two tiles behind the archer and
-- open ground (a ledge) within two tiles ahead. Such archers hold the
-- edge instead of pacing back and forth in a box.
local function perch(e, world)
  local tw = config.tile_size
  local wall_behind = false
  for d = 1, 2 * tw do
    local bx = e.facing > 0 and (e.x - d) or (e.x + e.w - 1 + d)
    if world:solid_at(bx, e.y + e.h/2) then wall_behind = true break end
  end
  if not wall_behind then return false end
  for d = 0, 2 * tw - 1 do
    local ax = e.facing > 0 and (e.x + e.w + d) or (e.x - 1 - d)
    if not world:solid_at(ax, e.y + e.h) then return true end
  end
  return false
end

-- One 30hz tick of a single enemy.
function Enemies.update_one(ctx, e)
  local p = ctx.player
  local world = ctx.world
  local cfg = config.enemies

  e.vy = math.min(e.vy + config.physics.gravity, config.physics.max_fall_speed)
  e.gr = false
  e.y  = e.y + e.vy
  world:resolve_y(e)
  world:resolve_slopes(e)

  if e.gr then
    if e.type == "archer" then
      if e.state == "aim" or e.state == "wait" then
        e.vx = 0  -- stands still while preparing or between volleys
      elseif e.state == "investigate" then
        -- walk toward the last known player position; ledges don't
        -- stop the search (walls still block via resolve_x below) --
        -- but a drop deeper than max_drop_tiles does: it decides to
        -- stay on its platform and gives the search up
        local dir = (e.last_known.x >= e.x + e.w/2) and 1 or -1
        local px = dir > 0 and (e.x + e.w) or (e.x - 1)
        local ledge_ahead = not world:solid_at(px, e.y + e.h)
        local max_drop = cfg.max_drop_tiles * config.tile_size
        if ledge_ahead
        and world:drop_depth(px, e.y + e.h, max_drop) > max_drop then
          e.state = "patrol"
        else
          e.facing = dir
          e.vx = cfg.archer_speed * dir
        end
      elseif perch(e, world) then
        -- backed against a wall on a small platform: hold the edge
        local px = e.facing > 0 and (e.x + e.w) or (e.x - 1)
        if not world:solid_at(px, e.y + e.h) then
          e.vx = 0  -- toes at the edge, holding position
        else
          e.vx = cfg.archer_speed * e.facing  -- walk out to the edge
        end
      else
        patrol(e, cfg.archer_speed, world)
      end
    else
      patrol(e, cfg.melee_speed, world)
    end
  else
    e.vx = e.vx * cfg.air_drag
  end

  e.x = e.x + e.vx
  world:resolve_x(e)

  if e.x < 0 then e.x = 0 e.facing = 1 end
  if e.x+e.w > world.px_w then e.x = world.px_w-e.w e.facing = -1 end

  if e.type == "melee" and Util.aabb(e, p) then
    -- impact direction runs from the enemy toward the player, so the
    -- blood spray (opposite it) flies away from the attacker
    ctx.hurt(ctx, p.x - e.x, p.y - e.y)
    return
  end

  if e.type == "archer" then
    if e.shoot_cd > 0 then e.shoot_cd = e.shoot_cd - 1 end
    -- release a staggered volley's remaining arrows as timers lapse
    if e.volley then
      for i = #e.volley, 1, -1 do
        local shot = e.volley[i]
        shot.t = shot.t - 1
        if shot.t <= 0 then
          Enemies.spawn_e_arrow(ctx, e.x + e.w/2, e.y + e.h/2, shot.angle)
          table.remove(e.volley, i)
        end
      end
      if #e.volley == 0 then e.volley = nil end
    end
    archer_brain(ctx, e)
  end
end

-- One 30hz step over all enemies; only enemies near the camera are
-- simulated.
function Enemies.update(ctx)
  local ents, cam = ctx.ents, ctx.cam
  local vw = config.view.width
  local m, M = 640, vw + 640
  for i = #ents.enemies, 1, -1 do
    local e = ents.enemies[i]
    if e.x >= cam.x - m and e.x <= cam.x + M
    and e.y >= cam.y - 512 and e.y <= cam.y + config.view.height + 512 then
      Enemies.update_one(ctx, e)
    end
  end
end

return Enemies
