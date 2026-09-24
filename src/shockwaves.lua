-- Shockwaves: the bow's concussive pulse (the swap cycle's third arrow
-- kind, replacing the propel arrow). A short-lived wave fired out from
-- the bow as a SEMICIRCLE: the front is a 180-degree cone of force
-- opening along the aim direction, its flat back edge riding through
-- the wave centre, so only what lies ahead of the wave gets swept --
-- the shooter, behind that edge, is untouched by their own shot. It
-- flies straight (no gravity), bounces off any surface (the reflection
-- re-aims the cone for free, since the heading IS the velocity), grows
-- as it travels -- a wider front is easier to connect with -- and
-- fizzles out after only a mild distance. It is harmless but shoves
-- hard: whatever the front sweeps gets an impulse along the radial from
-- the wave centre -- enemies (never killed), the player (only a
-- turned-around front can reach them, so a fresh shot can never fling
-- the shooter) and enemy projectiles (darts and bombs knocked off
-- course, rockets knocked away from their cruise heading). Firing one
-- also cuts an attached rope: it is a mobility tool.

local config = require("src.config")
local Util   = require("src.util")
local Particles = require("src.particles")

local Shockwaves = {}

-- True when the wave's forward half-disc -- the 180-degree cone of force
-- opening along its travel, with its flat back edge running through the
-- wave centre perpendicular to travel -- reaches the box b: the box's
-- closest point to the centre must lie within the radius AND in front of
-- that back edge. (When the centre is inside the box the closest point is
-- the centre itself, whose forward dot is exactly zero: swallowed targets
-- still count.)
local function cone_hits_box(w, b)
  local nx = math.max(b.x, math.min(w.x, b.x + b.w))
  local ny = math.max(b.y, math.min(w.y, b.y + b.h))
  local dx, dy = w.x - nx, w.y - ny
  if dx*dx + dy*dy > w.r * w.r then return false end
  return w.vx * (nx - w.x) + w.vy * (ny - w.y) >= 0
end

-- The same forward-half-disc test for a bare point (a bomb's or a
-- dart's centre).
local function cone_hits_point(w, px, py)
  local dx, dy = px - w.x, py - w.y
  if dx*dx + dy*dy > w.r * w.r then return false end
  return w.vx * dx + w.vy * dy >= 0
end

-- Unit shove direction from the wave centre toward (tx, ty), falling
-- back to the wave's own travel direction at zero distance (a wave
-- that bounced straight back through its shooter still shoves them
-- along its motion).
local function shove_dir(w, tx, ty)
  local dx, dy = tx - w.x, ty - w.y
  local d = math.sqrt(dx*dx + dy*dy)
  if d > 0 then return dx/d, dy/d end
  local s = math.sqrt(w.vx*w.vx + w.vy*w.vy)
  if s > 0 then return w.vx/s, w.vy/s end
  return 0, -1
end

-- Spawns the wave at the player's bow centre along `angle` (a pico-8
-- turn, 0..1) at the current power level's wave speed, scaled by
-- `force` (analog stick tilt). Waves never use the arrow quiver: their
-- own airborne cap silently drops excess shots.
function Shockwaves.spawn(ctx, angle, force)
  local ents, p = ctx.ents, ctx.player
  local cfg = ctx.config.shockwave
  if #ents.shockwaves >= cfg.max_active then return end
  local dx, dy = Util.p8cos(angle), Util.p8sin(angle)
  local spd = cfg.speeds[p.aim_power]
    * math.max(force or 1, cfg.min_force_scale)
  table.insert(ents.shockwaves, {
    x = p.x + p.w/2, y = p.y + p.h/2,
    vx = dx * spd, vy = dy * spd,
    r = cfg.radius_start,
    traveled = 0,   -- px flown; the fizzle clock and growth driver
    active = true,
    bounced = 0,    -- bounces so far: the front may shove the player
                    -- only after the first one (a turned-around wave)
    pushed = {},    -- targets shoved this leg (cleared on bounce)
  })
end

-- One sim step of a wave's flight (world time = ctx.dt steps). Flight
-- is substepped like the arrows so a fast wave never skips a target:
-- collision, the fizzle clock and the pushes are sampled every few
-- pixels along the step's path.
function Shockwaves.step_one(ctx, w)
  local ents, world = ctx.ents, ctx.world
  local p = ctx.player
  local cfg = ctx.config.shockwave
  local efg = ctx.config.enemies
  local dt = ctx.dt

  local nsub = math.max(1, math.ceil(
    (math.abs(w.vx) + math.abs(w.vy)) * dt / cfg.substep_pixels))
  local sx, sy = w.vx * dt / nsub, w.vy * dt / nsub
  local step_len = math.sqrt(sx*sx + sy*sy)
  local pcx, pcy = p.x + p.w/2, p.y + p.h/2
  for _ = 1, nsub do
    local nx, ny = w.x + sx, w.y + sy

    -- terrain: bounce off anything it touches (the wave is a pulse;
    -- nothing sticks), reflecting like the arrow's sticky bounce. The
    -- step ends against the surface; the reflected leg runs next step.
    -- A spark burst off the impact point marks the ricochet (the flecks
    -- spray back along the wave's incoming direction, away from the wall).
    if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
      local ivx, ivy = w.vx, w.vy
      local hx = world:solid_for_arrow(nx, w.y) or world:in_slope_solid(nx, w.y)
      local hy = world:solid_for_arrow(w.x, ny) or world:in_slope_solid(w.x, ny)
      if hx then w.vx = -w.vx end
      if hy then w.vy = -w.vy end
      if not hx and not hy then w.vx, w.vy = -w.vx, -w.vy end
      Particles.sparks(ents, nx, ny, ivx, ivy)
      w.bounced = (w.bounced or 0) + 1
      w.pushed = {}   -- a fresh leg can shove the same things again
      -- a bounce that lands while the centre is still inside the
      -- player's box (a floor flush with their feet, a wall they are
      -- pressed against) means the reflected front is heading straight
      -- back through them: shove immediately, no exit-and-return wait
      if not w.pushed[p]
      and cone_hits_box(w, p) then
        local kx, ky = shove_dir(w, pcx, pcy)
        p.vx, p.vy = p.vx + kx * cfg.push, p.vy + ky * cfg.push
        if p.vy < 0 then
          p.gr = false
          p.j_frames = 0
        end
        w.pushed[p] = true
      end
      break
    end

    w.x, w.y = nx, ny
    w.traveled = w.traveled + step_len
    -- the front grows with the distance flown, up to the full size it
    -- reaches at the fizzle range
    local grown = math.min(1, w.traveled / cfg.max_range)
    w.r = cfg.radius_start + (cfg.radius_max - cfg.radius_start) * grown

    -- fizzle out at max range
    if w.traveled >= cfg.max_range then
      Particles.poof(ents, w.x, w.y)
      w.active = false
      return
    end

    -- shove the player when the front's cone reaches them and the wave
    -- has bounced at least once: a fresh shot is born at the bow with
    -- its flat back edge running through the shooter, so the first leg
    -- -- however the player's own fall repositions them past the
    -- centre -- can never fling them (they sit behind or on the back
    -- edge, outside the swept cone). Only a front that has turned
    -- around (a wall ahead, the floor under their feet, a ceiling
    -- overhead) opens back onto them: the reflected cone sweeps them
    -- along the radial from the wave centre (a dead-centre hit shoves
    -- along the wave's own travel, cone_hits' zero-dot case).
    if (w.bounced or 0) > 0
    and not w.pushed[p]
    and cone_hits_box(w, p) then
      local kx, ky = shove_dir(w, pcx, pcy)
      p.vx, p.vy = p.vx + kx * cfg.push, p.vy + ky * cfg.push
      if p.vy < 0 then
        p.gr = false
        p.j_frames = 0
      end
      w.pushed[p] = true
    end

    -- enemies: shoved along the radial, never killed (the growing cone
    -- is the generous target)
    for _, e in ipairs(ents.enemies) do
      if not w.pushed[e] and cone_hits_box(w, e) then
        local kx, ky = shove_dir(w, e.x + e.w/2, e.y + e.h/2)
        e.vx, e.vy = e.vx + kx * cfg.push, e.vy + ky * cfg.push
        if e.vy < 0 then e.gr = false end
        w.pushed[e] = true
      end
    end

    -- rockets: knocked away from the wave (the homing re-curves them
    -- later; the knock rides the rocket's own damped drift vector)
    local hw, hh = efg.rocket_hit_w, efg.rocket_hit_h
    for _, r in ipairs(ents.rockets) do
      if r.active and not w.pushed[r] then
        local box = { x = r.x - hw/2, y = r.y - hh/2, w = hw, h = hh }
        if cone_hits_box(w, box) then
          local kx, ky = shove_dir(w, r.x, r.y)
          r.kx, r.ky = kx * cfg.push, ky * cfg.push
          w.pushed[r] = true
        end
      end
    end

    -- bombs: shoved, never detonated (a knocked bomb can be bounced
    -- back toward its thrower's friends)
    for _, b in ipairs(ents.bombs) do
      if b.active and not w.pushed[b]
      and cone_hits_point(w, b.x, b.y) then
        local kx, ky = shove_dir(w, b.x, b.y)
        b.vx, b.vy = b.vx + kx * cfg.push, b.vy + ky * cfg.push
        w.pushed[b] = true
      end
    end

    -- enemy arrows: darts deflected off course (the front sweeps over
    -- the volley ahead of it and scatters it)
    for _, a in ipairs(ents.e_arrows) do
      if a.active and not a.hit_stick and not w.pushed[a]
      and cone_hits_point(w, a.x, a.y) then
        local kx, ky = shove_dir(w, a.x, a.y)
        a.vx, a.vy = a.vx + kx * cfg.push, a.vy + ky * cfg.push
        w.pushed[a] = true
      end
    end

    if w.x < -20 or w.y < -20
    or w.x > world.px_w or w.y > world.px_h then
      w.active = false
      return
    end
  end
end

-- One sim step over all shockwaves (world time = ctx.dt steps). The
-- list is read fresh each iteration: a mid-loop player death resets it
-- (the loop then ends early).
function Shockwaves.update(ctx)
  local ents = ctx.ents
  for i = #ents.shockwaves, 1, -1 do
    local w = ents.shockwaves[i]
    if not w then break end
    if not w.active then
      table.remove(ents.shockwaves, i)
    elseif ctx.world:in_room(w.x, w.y) then
      Shockwaves.step_one(ctx, w)
    end  -- waves beyond the active room hang frozen (off-screen)
  end
end

return Shockwaves
