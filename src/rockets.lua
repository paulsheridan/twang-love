-- Rockets: the rocketeer's homing ordnance (plus the explosion flashes
-- they leave behind). Rockets launch straight up from just above the
-- shooter's head, climb a short way and hang there briefly -- the
-- player's window to shoot one down -- then turn on a dime toward the
-- player's live position and hunt in pursuit arcs. Since the flight
-- ignores terrain until contact, cover does not protect against them.
-- Detonations trip on proximity to the player, terrain contact, or age;
-- the blast hurts the player and kills any enemy caught in it (arrows
-- are the game's only other killer, and they remove instantly too).

local config = require("src.config")
local Particles = require("src.particles")

local Rockets = {}

-- True when a circle at (cx, cy) with radius r overlaps the box b
-- (closest-point test: the box corner nearest the centre).
local function circle_hits_box(cx, cy, r, b)
  local nx = math.max(b.x, math.min(cx, b.x + b.w))
  local ny = math.max(b.y, math.min(cy, b.y + b.h))
  local dx, dy = cx - nx, cy - ny
  return dx*dx + dy*dy <= r * r
end

-- Detonates at (x, y): an expanding flash, a spark burst and a poof,
-- blast damage to the player (2 half-hearts) and instant removal of any
-- enemy caught in the radius. Other rockets are unaffected.
function Rockets.explode(ctx, x, y)
  local cfg = ctx.config.enemies
  Rockets.blast(ctx, x, y, cfg.rocket_blast_radius, cfg.rocket_half_hearts)
end

-- The shared blast every explosive detonates through (rockets and the
-- bomber's thrown bombs alike): a flash ring sized to `radius`, the
-- spark/poof burst, damage to the player caught in it and instant
-- removal of any enemy in the radius. `radius` rides on the boom entry
-- so the flash draws itself out to the right size.
function Rockets.blast(ctx, x, y, radius, half_hearts)
  local ents = ctx.ents
  table.insert(ents.booms, { x = x, y = y, t = ctx.config.enemies.boom_frames,
    r = radius })
  Particles.boom(ents, x, y)
  Particles.poof(ents, x, y)
  local p = ctx.player
  if circle_hits_box(x, y, radius, p) then
    ctx.hurt(ctx, p.x + p.w/2 - x, p.y + p.h/2 - y, half_hearts)
  end
  for i = #ents.enemies, 1, -1 do
    local e = ents.enemies[i]
    if circle_hits_box(x, y, radius, e) then
      -- impact direction runs from the enemy toward the blast, so the
      -- blood spray flies away from the explosion
      Particles.blood(ents, e.x + e.w/2, e.y + e.h/2, x - e.x, y - e.y)
      table.remove(ents.enemies, i)
    end
  end
end

-- Spawns a rocket just above a shooter's head, launching straight up
-- with a small random heading offset (so salvos don't stack perfectly).
-- The global airborne cap (rocket_max_alive) drops excess launches.
-- A rocket carries a unit heading (hx, hy) instead of a free velocity:
-- the flight phases steer the heading and the speed comes from config.
-- `kx`/`ky` is a knock vector (a shockwave hit sets it) that drifts the
-- rocket on top of its steered cruise, damped out each step.
function Rockets.spawn(ctx, x, y)
  local cfg = ctx.config.enemies
  if #ctx.ents.rockets >= cfg.rocket_max_alive then return nil end
  local a = (math.random() * 2 - 1) * cfg.rocket_jitter
  local r = {
    x = x, y = y,
    hx = math.sin(a), hy = -math.cos(a),
    state = "climb",   -- climb -> hover -> attack (see step_rocket)
    climbed = 0,
    hover_t = 0,
    active = true,
    lt = cfg.rocket_lifetime,
    trail_t = cfg.rocket_trail_every,
    kx = 0, ky = 0,
  }
  table.insert(ctx.ents.rockets, r)
  return r
end

-- One sim step of a rocket in flight (world time = ctx.dt steps). The
-- flight runs in three phases:
--   climb  straight up, no steering, until rocket_hover_height is
--          climbed above the launch point
--   hover  it hangs there (velocity zero) for rocket_hover_steps --
--          the player's window to shoot it down while it hangs
--   attack the heading snaps to the player's live centre (on a dime),
--          then pure pursuit: the heading steers toward them at up to
--          rocket_turn_rate per step while the speed stays constant
-- The motion is substepped so the fuse and terrain are never skipped.
local function step_rocket(ctx, r)
  local cfg = ctx.config.enemies
  local p, world = ctx.player, ctx.world
  local speed = cfg.rocket_speed

  r.lt = r.lt - ctx.dt
  if r.lt <= 0 then
    Rockets.explode(ctx, r.x, r.y)
    r.active = false
    return
  end

  -- the fuse reads the player's live centre: a player who jumps into a
  -- hovering rocket pops it too
  local tx, ty = p.x + p.w/2, p.y + p.h/2
  local pdx, pdy = tx - r.x, ty - r.y
  if pdx*pdx + pdy*pdy <= cfg.rocket_proximity * cfg.rocket_proximity then
    Rockets.explode(ctx, r.x, r.y)
    r.active = false
    return
  end

  local move = 0
  if r.state == "climb" then
    local remaining = cfg.rocket_hover_height - r.climbed
    move = math.min(speed * ctx.dt, math.max(0, remaining))
    r.climbed = r.climbed + move
    if r.climbed >= cfg.rocket_hover_height then
      r.state = "hover"
      r.hover_t = cfg.rocket_hover_steps
    end
  elseif r.state == "hover" then
    r.hover_t = r.hover_t - ctx.dt
    if r.hover_t <= 0 then
      -- turn on a dime: the heading snaps to the player's live position
      local dx, dy = tx - r.x, ty - r.y
      local dl = math.sqrt(dx*dx + dy*dy)
      if dl > 0 then
        r.hx, r.hy = dx/dl, dy/dl
      end
      r.state = "attack"
    end
  else
    -- attack: pure pursuit toward the player's live centre
    local dx, dy = tx - r.x, ty - r.y
    local dl = math.sqrt(dx*dx + dy*dy)
    if dl > 0 then
      dx, dy = dx/dl, dy/dl
      local max_turn = cfg.rocket_turn_rate * ctx.dt
      -- signed angle from the current heading to the desired one
      local ang = math.atan2(r.hx*dy - r.hy*dx, r.hx*dx + r.hy*dy)
      if math.abs(ang) <= max_turn then
        r.hx, r.hy = dx, dy
      else
        local t = (ang >= 0) and max_turn or -max_turn
        local c, s = math.cos(t), math.sin(t)
        r.hx, r.hy = r.hx*c - r.hy*s, r.hx*s + r.hy*c
      end
    end
    move = speed * ctx.dt
  end

  -- flight motion: the steered cruise (heading * speed) plus any
  -- shockwave knock (a wave-hit rocket drifts along the knock vector,
  -- damped each step, until it fades out)
  local kx, ky = r.kx or 0, r.ky or 0
  local mvx, mvy = r.hx * move + kx * ctx.dt, r.hy * move + ky * ctx.dt
  local mlen = math.sqrt(mvx*mvx + mvy*mvy)
  if mlen > 0 then
    local nsub = math.max(1, math.ceil(mlen / cfg.rocket_substep))
    local sx, sy = mvx / nsub, mvy / nsub
    for _ = 1, nsub do
      local nx, ny = r.x + sx, r.y + sy
      if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
        Rockets.explode(ctx, r.x, r.y)  -- just short of the wall, not in it
        r.active = false
        return
      end
      r.x, r.y = nx, ny
      local fdx, fdy = tx - r.x, ty - r.y
      if fdx*fdx + fdy*fdy <= cfg.rocket_proximity * cfg.rocket_proximity then
        Rockets.explode(ctx, r.x, r.y)
        r.active = false
        return
      end
    end
  end

  -- knock decay: the shove is a momentary impulse, not a new heading
  if kx ~= 0 or ky ~= 0 then
    local damp = math.max(0, 1 - 0.3 * ctx.dt)
    r.kx, r.ky = kx * damp, ky * damp
    if math.abs(r.kx) < 0.05 then r.kx = 0 end
    if math.abs(r.ky) < 0.05 then r.ky = 0 end
  end

  -- smoke trail a little behind the tail (a hovering rocket idles too)
  r.trail_t = r.trail_t - ctx.dt
  if r.trail_t <= 0 then
    Particles.smoke(ctx.ents, r.x - r.hx * 6, r.y - r.hy * 6)
    r.trail_t = cfg.rocket_trail_every
  end

  if r.y < -20 or r.x < -20
  or r.x > world.px_w or r.y > world.px_h then
    r.active = false
  end
end

-- One sim step over all rockets and explosion flashes (world time =
-- ctx.dt steps). The lists are read fresh each iteration: a mid-loop
-- player death resets them (the loops then end early).
function Rockets.update(ctx)
  local ents = ctx.ents
  for i = #ents.rockets, 1, -1 do
    local r = ents.rockets[i]
    if not r then break end
    if not r.active then
      table.remove(ents.rockets, i)
    elseif ctx.world:in_room(r.x, r.y) then
      step_rocket(ctx, r)
      if not r.active then table.remove(ents.rockets, i) end
    end  -- rockets beyond the active room hang frozen (off-screen)
  end
  for i = #ents.booms, 1, -1 do
    local b = ents.booms[i]
    if not b then break end
    b.t = b.t - ctx.dt
    if b.t <= 0 then table.remove(ents.booms, i) end
  end
end

return Rockets
