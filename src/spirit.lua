-- Spirit: the bow's recoil-launch (the swap cycle's third arrow kind,
-- replacing the shockwave pulse). Firing it fires NO arrow at all: the
-- bow releases a burst of ghostly force at the player's centre, and the
-- body is flung the opposite way -- "any direction you fire, you fly
-- the other". The rocket-jump tool with nothing to wait for: the
-- impulse is instant, added to the body's motion (it stacks with jump,
-- swing and fall momentum, the point of the tool) and rides the
-- winch-throw grace window so the walk cap cannot clamp it. Firing
-- also cuts an attached rope: it is a mobility tool. While the kind is
-- equipped the player reads as ghostly blue (the render pass tints
-- them, see src/render/player.lua).
--
-- Two rules make it a traversal tool rather than a flight cheat:
--
--   * ONE fling between landings: the charge fills every step the
--     player stands on solid ground (Player.physics sets it) and burns
--     at the shot. A spent bow clicks: no fling, no burst, no rope cut.
--   * the second-jump rule: whenever the knock points up (the aim is
--     below level), the fling must rise a FULL JUMP's height above the
--     fired point even through the body's current fall -- the knock at
--     least cancels the fall and still launches at the player's jump
--     speed (plus the one gravity tick the first integration tick pays
--     before it moves), while stronger intended flings keep their edge.
--
-- There is nothing to simulate: Spirit.fire is a single fire-time
-- application. No projectile, no persistent entity, no update loop,
-- no boom flash either -- the burst of particles is the whole show.

local config = require("src.config")
local Util   = require("src.util")
local Particles = require("src.particles")

local Spirit = {}

-- The spirit arrow's fire: a burst of particles at the player's centre
-- (streaming back along the aim, the force's exhaust) and the fling
-- itself: an impulse ADDED to the body's velocity along the exact
-- opposite of the aim direction, at the current power level's push
-- strength, scaled by `force` (analog stick tilt), floored at a full
-- jump's rise when the fling points up.
--
-- Nothing else happens: no arrow entity, no wave, no collisions. The
-- burst marks the force; the fling is the effect.
function Spirit.fire(ctx, angle, force)
  local ents, p = ctx.ents, ctx.player
  local cfg = ctx.config.spirit

  -- the once-per-airtime charge (Player.physics refills it every step
  -- the body stands on solid ground); a spent bow clicks, firing
  -- nothing -- not even a rope cut
  if not p.spirit_armed then return end
  p.spirit_armed = false

  -- firing cuts an attached rope: a mobility tool, like every bow shove
  p.rope = nil
  p.rope_cd = cfg.shove_grace

  -- the fling: the aim unit vector reversed, at the power level's push
  local dx, dy = Util.p8cos(angle), Util.p8sin(angle)
  local spd = cfg.push[p.aim_power]
    * math.max(force or 1, cfg.min_force_scale)
  local knock_vy = -dy * spd
  -- the second-jump rule: an upward knock must rise a full jump's
  -- height from the fired point THROUGH the current fall -- launch at
  -- the jump speed plus the first integration tick's gravity (the tick
  -- is one world-time step: gravity * 30/sim.rate, 1 at 30hz).
  -- (j is negative; a stronger intended fling already clears this floor)
  if dy > 0 then
    local tick = 30 / ctx.config.sim.rate
    local floor_vy = config.player.jump_velocity
                   - config.physics.gravity * tick
    if p.vy + knock_vy > floor_vy then
      knock_vy = floor_vy - p.vy
    end
  end
  p.vx, p.vy = p.vx - dx * spd, p.vy + knock_vy

  -- the launch plays out untouched for shove_grace steps (movement
  -- input ignored, no walk cap) until it lapses or the player lands
  p.winch_grace = cfg.shove_grace

  -- the burst: a ghostly-blue spark jet streaming out along the AIM
  -- direction (the force's exhaust) with a white core
  Particles.spirit_burst(ents, p.x + p.w/2, p.y + p.h/2, dx, dy)
end

return Spirit
