-- Enemies: patrolling melee contact-killers, archers, laser riflemen
-- and rocketeers with a sense -> combat -> cover fire -> investigate
-- brain. Every enemy tracks the player's position every step it is
-- visible; when sight breaks the ranged enemies keep firing at the last
-- known position for enemies.suppress_steps (cover fire), then
-- investigate; the melee sprints after the player while it is seen.
-- Seeing the player again always returns them to combat. Patrols are
-- bounded: an enemy turns back at walls, ledges, or enemies.roam_tiles
-- from its spawn point.
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
local Particles = require("src.particles")
local Rockets = require("src.rockets")

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

-- ==== laser rifleman ====

-- Points the laser at (tx, ty): stores the unit aim direction and the
-- px distance to the target on the enemy (the beam fires along the
-- direction solved when the sight line first appears -- the aim stays
-- locked through the telegraph, so the flash and the shot share one
-- vector).
local function solve_beam_aim(ctx, e, tx, ty)
  if e.aim_dx then return end  -- the telegraph keeps its locked direction
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local dx, dy = tx - ex, ty - ey
  local len = math.sqrt(dx*dx + dy*dy)
  if len > 0 then
    e.aim_dx, e.aim_dy = dx/len, dy/len
  else
    e.aim_dx, e.aim_dy = e.facing, 0
  end
  e.aim_len = Enemies.beam_range(ctx.world, ex, ey, e.aim_dx, e.aim_dy)
end

-- Px distance along a unit vector from (x, y) to the world's bounds.
local function range_to_bounds(x, y, ux, uy, w, h)
  local t = math.huge
  if ux > 0 then t = math.min(t, (w - x) / ux) end
  if ux < 0 then t = math.min(t, -x / ux) end
  if uy > 0 then t = math.min(t, (h - y) / uy) end
  if uy < 0 then t = math.min(t, -y / uy) end
  if t == math.huge or t < 0 then t = 0 end
  return t
end

-- Marches a ray from (x, y) along the unit vector (ux, uy) until it hits
-- terrain (anything arrows cannot fly through, plus slopes) or leaves the
-- world, and returns the px distance travelled. Exposed for tests.
function Enemies.beam_range(world, x, y, ux, uy)
  local cfg = config.enemies
  local step = cfg.laser_ray_step
  local bound = range_to_bounds(x, y, ux, uy, world.px_w, world.px_h)
  local d = 0
  while d < bound do
    local nd = math.min(d + step, bound)
    if world:solid_for_arrow(x + ux*nd, y + uy*nd)
    or world:in_slope_solid(x + ux*nd, y + uy*nd) then
      return nd
    end
    d = nd
  end
  return bound
end

-- Distance along the beam segment from (ex, ey) along the unit vector
-- (ux, uy) for `len` px to where it first enters the player's box,
-- grown by `pad` px on every side, or nil when it misses (the slab
-- test: the segment must enter both the box's x and y slabs).
local function beam_hit_t(ex, ey, ux, uy, len, p, pad)
  local tmin, tmax = 0, len
  if ux == 0 then
    if ex < p.x - pad or ex > p.x + p.w + pad then return nil end
  else
    local t1 = (p.x - pad - ex) / ux
    local t2 = (p.x + p.w + pad - ex) / ux
    if t1 > t2 then t1, t2 = t2, t1 end
    tmin = math.max(tmin, t1)
    tmax = math.min(tmax, t2)
  end
  if uy == 0 then
    if ey < p.y - pad or ey > p.y + p.h + pad then return nil end
  else
    local t1 = (p.y - pad - ey) / uy
    local t2 = (p.y + p.h + pad - ey) / uy
    if t1 > t2 then t1, t2 = t2, t1 end
    tmin = math.max(tmin, t1)
    tmax = math.min(tmax, t2)
  end
  if tmax >= tmin then return tmin end
  return nil
end

-- Fires the laser: the beam flashes along the direction the sight line
-- locked in when the telegraph began, marched out to the first wall (or
-- the world's edge) -- but a beam that would reach the player stops dead
-- at them instead: the impact throws sparks off the contact point and
-- the hit lands right away (a full heart, unless i-frames shield it).
-- The beam is a brief flash.
function Enemies.fire_beam(ctx, e)
  local cfg = config.enemies
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local dx, dy = e.aim_dx or e.facing, e.aim_dy or 0
  local len = math.sqrt(dx*dx + dy*dy)
  if len > 0 then dx, dy = dx/len, dy/len else dx, dy = e.facing, 0 end
  len = Enemies.beam_range(ctx.world, ex, ey, dx, dy)
  local hit = beam_hit_t(ex, ey, dx, dy, len, ctx.player,
    (cfg.laser_beam_width - 2) / 2)
  if hit then
    len = hit  -- the beam stops at the player, not through them
  end
  e.beam = {
    dx = dx, dy = dy,
    len = len,
    t = cfg.laser_beam_steps,
    hit = hit and true or nil,
  }
  e.shoot_cd = cfg.shoot_cooldown
  if hit then
    Particles.sparks(ctx.ents, ex + dx*hit, ey + dy*hit, dx, dy)
    ctx.hurt(ctx, dx, dy, cfg.laser_half_hearts)
  end
end

-- ==== rocketeer ====

-- The rocketeer needs no ballistic solve: the rocket launches straight
-- up from just above its head and homes from there (the telegraph
-- timer alone charges the shot; the brain still tracks the player and
-- turns to face it while it is visible).
local function solve_rocket_aim(ctx, e, tx, ty) end

-- Fires one rocket just above the rocketeer's head.
function Enemies.fire_rocket(ctx, e)
  local cfg = config.enemies
  Rockets.spawn(ctx, e.x + e.w/2, e.y - 4)
  e.shoot_cd = cfg.shoot_cooldown
end

-- ==== brains: ranged (archer + laser + rocketeer) and melee ====

-- Per-type knobs for the shared ranged brain. `solve` aims a shot at
-- (tx, ty), `fire` releases it, `clear_aim` wipes the solved fields
-- afterwards, the field names pick the telegraph length and the
-- follow-up cadence out of config.enemies, and `holds_blocked` pauses
-- the telegraph while the player is visible behind terrain (the
-- archer's ballistic solve only). A spec with `burst_count_field` set
-- fires that many shots per charge -- between them on the short burst
-- cadence, tracking the player -- before the full recharge applies
-- (the archer leaves it unset: every shot pays the full cadence).
local RANGED_SPECS = {
  archer = {
    aim_steps_field    = "aim_steps",
    rapid_min_field    = "rapid_min",
    rapid_extra_field  = "rapid_extra",
    solve              = solve_aim,
    fire               = Enemies.fire_volley,
    clear_aim          = function(e) e.aim_vx, e.aim_vy = nil, nil end,
    holds_blocked      = true,
  },
  laser = {
    aim_steps_field    = "laser_sight_steps",
    rapid_min_field    = "laser_rapid_min",
    rapid_extra_field  = "laser_rapid_extra",
    burst_count_field  = "laser_burst_count",
    burst_min_field    = "laser_burst_min",
    burst_extra_field  = "laser_burst_extra",
    solve              = solve_beam_aim,
    fire               = Enemies.fire_beam,
    clear_aim          = function(e)
      e.aim_dx, e.aim_dy, e.aim_len = nil, nil, nil
    end,
    holds_blocked      = false,
  },
  rocketeer = {
    aim_steps_field    = "rocket_aim_steps",
    rapid_min_field    = "rocket_rapid_min",
    rapid_extra_field  = "rocket_rapid_extra",
    burst_count_field  = "rocket_burst_count",
    burst_min_field    = "rocket_burst_min",
    burst_extra_field  = "rocket_burst_extra",
    solve              = solve_rocket_aim,
    fire               = Enemies.fire_rocket,
    clear_aim          = function(e) end,
    holds_blocked      = false,
  },
}

-- Enters the aim state aimed at (tx, ty): combat aims at the tracked
-- spot (the tracking block below keeps it fresh while the player is
-- visible); a cover aim solves at the last known position and never
-- re-tracks (the shooter is firing blind). `fresh_charge` opens a new
-- shot budget for burst-firing specs (mid-burst telegraphs keep theirs).
local function enter_aim(ctx, e, spec, tx, ty, fresh_charge)
  e.state = "aim"
  e.aim_t = config.enemies[spec.aim_steps_field]
  if spec.burst_count_field and fresh_charge then
    e.burst = config.enemies[spec.burst_count_field]
  end
  spec.solve(ctx, e, tx, ty)
end

-- One sim tick of a ranged enemy's brain (world time = ctx.dt steps),
-- shared by archers, laser riflemen and rocketeers via RANGED_SPECS:
--
--   * the player's position is tracked every step it stays visible, in
--     every state (combat aims at the live spot; cover fire and searches
--     aim at the freshest known spot)
--   * combat: aim (telegraphed) -> fire -> a quick, semi randomized
--     follow-up cadence while the player stays visible; burst-firing
--     specs (the laser) instead spend a shot budget per charge -- shots
--     follow one another on the short burst cadence, tracking the
--     player, and the full recharge only comes once it is spent
--   * sight broken: a cover-fire window opens -- the shooter stands
--     still and keeps firing at the last known position (blind shots on
--     the same cadence) for enemies.suppress_steps, then investigates
--   * a shot already mid-telegraph when sight breaks still fires at the
--     last solved direction, then the window keeps covering
--   * seeing the player again -- during cover fire or a search --
--     returns to combat at once; enemies.shoot_cooldown only gates a
--     patroller's first spot
local function ranged_brain(ctx, e, spec)
  local cfg = config.enemies
  local dt = ctx.dt
  local seen = Enemies.sees(ctx, e)
  if seen then
    local p = ctx.player
    e.last_known = {x = p.x + p.w/2, y = p.y + p.h/2}
  end

  if e.state == "aim" then
    if seen then
      e.suppress_t = nil  -- combat again: any cover-fire window is over
      spec.solve(ctx, e, e.last_known.x, e.last_known.y)
      e.facing = (e.last_known.x >= e.x + e.w/2) and 1 or -1  -- face the aim
      if not (spec.holds_blocked and e.aim_blocked) then
        e.aim_t = e.aim_t - dt
      end
    else
      e.aim_t = e.aim_t - dt
      if e.suppress_t then e.suppress_t = e.suppress_t - dt end
    end
    if e.aim_t <= 0 then
      spec.fire(ctx, e)
      spec.clear_aim(e)
      if seen then
        e.state = "wait"
        if spec.burst_count_field and e.burst and e.burst > 1 then
          -- mid-burst: the next shot follows on the short cadence
          e.burst = e.burst - 1
          e.wait_t = cfg[spec.burst_min_field]
            + math.random(0, cfg[spec.burst_extra_field])
        else
          -- the charge is spent: quick, slightly randomized recharge
          if spec.burst_count_field then e.burst = 0 end
          e.wait_t = cfg[spec.rapid_min_field]
            + math.random(0, cfg[spec.rapid_extra_field])
        end
      else
        -- the player slipped away mid-shot: cover the last known spot
        e.state = "suppress"
        e.suppress_t = e.suppress_t or cfg.suppress_steps
        e.wait_t = cfg[spec.rapid_min_field]
          + math.random(0, cfg[spec.rapid_extra_field])
      end
    end
  elseif e.state == "wait" then
    if seen then
      local p = ctx.player
      e.facing = (p.x + p.w/2 >= e.x + e.w/2) and 1 or -1
      e.wait_t = e.wait_t - dt
      if e.wait_t <= 0 then
        -- mid-burst telegraphs keep the remaining shot budget; once it
        -- is spent (or never opened) this telegraph starts a fresh one
        local mid_burst = e.burst ~= nil and e.burst > 0
        enter_aim(ctx, e, spec, e.last_known.x, e.last_known.y, not mid_burst)
      end
    else
      -- sight broke mid-cadence: open the cover-fire window
      e.state = "suppress"
      e.suppress_t = cfg.suppress_steps
      e.wait_t = cfg[spec.rapid_min_field]
        + math.random(0, cfg[spec.rapid_extra_field])
    end
  elseif e.state == "suppress" then
    e.suppress_t = e.suppress_t - dt
    if seen then
      -- reacquired mid-cover: back to combat at once
      e.suppress_t = nil
      enter_aim(ctx, e, spec, e.last_known.x, e.last_known.y, true)
    else
      e.wait_t = e.wait_t - dt
      if e.wait_t <= 0 then
        enter_aim(ctx, e, spec, e.last_known.x, e.last_known.y, false)
      end
      if e.state == "suppress" and e.suppress_t <= 0 then
        -- covered long enough: go and look for the player
        e.state = "investigate"
        e.investigate_t = cfg.investigate_timeout
      end
    end
  elseif e.state == "investigate" then
    e.investigate_t = e.investigate_t - dt
    if seen then
      -- reacquired: back to combat at once (the cooldown gate only
      -- holds for a patroller's first spot)
      e.suppress_t = nil
      enter_aim(ctx, e, spec, e.last_known.x, e.last_known.y, true)
    elseif e.investigate_t <= 0
    or math.abs(e.x + e.w/2 - e.last_known.x) <= cfg.investigate_reach then
      e.state = "patrol"
    end
  else
    if seen and e.shoot_cd == 0 then
      enter_aim(ctx, e, spec, e.last_known.x, e.last_known.y, true)
    end
  end
end

-- One sim tick of the melee brain (world time = ctx.dt steps): sprint
-- after the player while it is visible, investigate the last known
-- position when sight breaks, patrol otherwise. Seeing the player again
-- always returns it to the chase.
local function melee_brain(ctx, e)
  local cfg = config.enemies
  local dt = ctx.dt
  local seen = Enemies.sees(ctx, e)
  if seen then
    local p = ctx.player
    e.last_known = {x = p.x + p.w/2, y = p.y + p.h/2}
  end

  if e.state == "chase" then
    if not seen then
      -- lost sight: go look where the player was
      e.state = "investigate"
      e.investigate_t = cfg.investigate_timeout
    end
  elseif e.state == "investigate" then
    e.investigate_t = e.investigate_t - dt
    if seen then
      e.state = "chase"
    elseif e.investigate_t <= 0
    or math.abs(e.x + e.w/2 - e.last_known.x) <= cfg.investigate_reach then
      e.state = "patrol"
    end
  else
    if seen then
      e.state = "chase"
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

-- Walk toward (tx): used by investigating and chasing enemies. Ledges
-- don't stop the walk (walls still block via resolve_x below) but a
-- drop deeper than enemies.max_drop_tiles does: the walker decides to
-- stay on its platform and gives the walk up. Returns false then, so
-- the caller can end it.
local function walk_toward(e, tx, spd, world)
  local dir = (tx >= e.x + e.w/2) and 1 or -1
  local px = dir > 0 and (e.x + e.w) or (e.x - 1)
  local ledge_ahead = not world:solid_at(px, e.y + e.h)
  local max_drop = config.enemies.max_drop_tiles * config.tile_size
  if ledge_ahead
  and world:drop_depth(px, e.y + e.h, max_drop) > max_drop then
    e.vx = 0  -- toes at the edge: the walk refuses to step off
    return false
  end
  e.facing = dir
  e.vx = spd * dir
  return true
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

-- One sim tick of a single enemy (world time = ctx.dt steps).
function Enemies.update_one(ctx, e)
  local p = ctx.player
  local world = ctx.world
  local cfg = config.enemies
  local dt = ctx.dt

  e.vy = math.min(e.vy + config.physics.gravity * dt, config.physics.max_fall_speed)
  e.gr = false
  e.y  = e.y + e.vy * dt
  world:resolve_y(e)
  world:resolve_slopes(e)

  if e.gr then
    if e.type == "melee" then
      -- sprint after the player while it is visible (the chase target
      -- is the tracked spot, refreshed every visible step); when sight
      -- breaks the search walks at patrol pace; either walk gives up at
      -- a drop deeper than max_drop_tiles
      if e.state == "chase" then
        local tx = e.last_known and e.last_known.x or e.x
        if not walk_toward(e, tx, cfg.melee_chase_speed, world) then
          e.state = "patrol"
        end
      elseif e.state == "investigate" then
        local tx = e.last_known and e.last_known.x or e.x
        if not walk_toward(e, tx, cfg.melee_speed, world) then
          e.state = "patrol"
        end
      else
        patrol(e, cfg.melee_speed, world)
      end
    else
      -- archers, laser riflemen and rocketeers share the
      -- patrol/investigate instincts
      local speed = (e.type == "laser" and cfg.laser_speed)
        or (e.type == "rocketeer" and cfg.rocketeer_speed)
        or cfg.archer_speed
      if e.state == "aim" or e.state == "wait" or e.state == "suppress" then
        e.vx = 0  -- stands still while aiming, recharging or covering
      elseif e.state == "investigate" then
        local tx = e.last_known and e.last_known.x or e.x
        if not walk_toward(e, tx, speed, world) then
          e.state = "patrol"
        end
      elseif perch(e, world) then
        -- backed against a wall on a small platform: hold the edge
        local px = e.facing > 0 and (e.x + e.w) or (e.x - 1)
        if not world:solid_at(px, e.y + e.h) then
          e.vx = 0  -- toes at the edge, holding position
        else
          e.vx = speed * e.facing  -- walk out to the edge
        end
      else
        patrol(e, speed, world)
      end
    end
  else
    -- per-step multiplicative damping, exponent-scaled to world time
    e.vx = e.vx * cfg.air_drag ^ dt
  end

  e.x = e.x + e.vx * dt
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
    if e.shoot_cd > 0 then e.shoot_cd = math.max(0, e.shoot_cd - dt) end
    -- release a staggered volley's remaining arrows as timers lapse
    if e.volley then
      for i = #e.volley, 1, -1 do
        local shot = e.volley[i]
        shot.t = shot.t - dt
        if shot.t <= 0 then
          Enemies.spawn_e_arrow(ctx, e.x + e.w/2, e.y + e.h/2, shot.angle)
          table.remove(e.volley, i)
        end
      end
      if #e.volley == 0 then e.volley = nil end
    end
    ranged_brain(ctx, e, RANGED_SPECS.archer)
  elseif e.type == "laser" then
    if e.shoot_cd > 0 then e.shoot_cd = math.max(0, e.shoot_cd - dt) end
    -- the live beam ages out after its brief flash; a player who walks
    -- into it stops the beam dead at them too (the impact lands then,
    -- with its sparks -- i-frames keep repeats off)
    if e.beam then
      e.beam.t = e.beam.t - dt
      if e.beam.t <= 0 then
        e.beam = nil
      elseif not e.beam.hit then
        local b = e.beam
        local ex, ey = e.x + e.w/2, e.y + e.h/2
        local t = beam_hit_t(ex, ey, b.dx, b.dy, b.len, p,
          (cfg.laser_beam_width - 2) / 2)
        if t then
          b.len = t
          b.hit = true
          Particles.sparks(ctx.ents, ex + b.dx*t, ey + b.dy*t, b.dx, b.dy)
          ctx.hurt(ctx, b.dx, b.dy, cfg.laser_half_hearts)
        end
      end
    end
    ranged_brain(ctx, e, RANGED_SPECS.laser)
  elseif e.type == "rocketeer" then
    -- rockets fly free once launched (src/rockets.lua steps them), so
    -- the brain only runs its telegraph/cadence side
    if e.shoot_cd > 0 then e.shoot_cd = math.max(0, e.shoot_cd - dt) end
    ranged_brain(ctx, e, RANGED_SPECS.rocketeer)
  elseif e.type == "melee" then
    melee_brain(ctx, e)
  end
end

-- One sim step over all enemies (world time = ctx.dt steps); only
-- enemies near the camera are simulated.
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
