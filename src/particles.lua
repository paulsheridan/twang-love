-- Particles: poofs (key releases, deaths, arrow expiry), blood,
-- laser-impact sparks, smoke, explosion bursts, heavy-hit debris shards,
-- scorch chunks and the burning aftermath anchored at impact sites.
--
-- Particles are simple world-space dots with velocity and a step lifetime
-- (`s` optionally sizes the drawn square; `g` overrides the shared
-- gravity so smoke can rise).

local config = require("src.config")

local Particles = {}

local function add(list, x, y, vx, vy, col, life, s, g)
  table.insert(list, {x = x, y = y, vx = vx, vy = vy, col = col, life = life,
    s = s, g = g})
end

-- An 8-particle puff of white; used whenever a key drops back into the
-- world (as in twang.p8), and when arrows expire or the player dies.
function Particles.poof(ents, x, y)
  local cfg = config.particles
  for _ = 1, cfg.poof_count do
    local a   = math.random() * math.pi * 2
    local spd = math.random() * 3 + 1
    add(ents.particles, x, y, math.cos(a)*spd, math.sin(a)*spd,
      cfg.poof_colour, math.random(cfg.poof_life[1], cfg.poof_life[2]))
  end
end

-- Blood spray in the direction opposite to the arrow's travel. `bvx`,
-- `bvy` is an optional base velocity added onto every particle (the
-- hit body's motion, so the spray doesn't lag behind a moving target).
function Particles.blood(ents, x, y, avx, avy, bvx, bvy)
  local cfg = config.particles
  local len = math.sqrt(avx*avx + avy*avy)
  if len == 0 then len = 1 end
  local base = math.atan2(-avy/len, -avx/len)
  for _ = 1, cfg.blood_count do
    local a   = base + math.random()*0.25 - 0.125
    local spd = math.random() * 3 + 1
    add(ents.particles, x, y, math.cos(a)*spd + (bvx or 0),
      math.sin(a)*spd + (bvy or 0),
      cfg.blood_colour, math.random(cfg.blood_life[1], cfg.blood_life[2]))
  end
end

-- Sparks thrown off a laser beam's impact with the player: hot flecks
-- bouncing back along the beam (away from the shooter, i.e. opposite
-- its travel) with a wide scatter. Alternates yellow/white for a
-- crackling read.
function Particles.sparks(ents, x, y, bdx, bdy)
  local cfg = config.particles
  local base = math.atan2(-bdy, -bdx)
  for i = 1, cfg.spark_count do
    local a   = base + math.random()*0.9 - 0.45
    local spd = math.random() * 4 + 1.5
    add(ents.particles, x, y, math.cos(a)*spd, math.sin(a)*spd,
      (i % 2 == 0) and cfg.spark_colour or 7,
      math.random(cfg.spark_life[1], cfg.spark_life[2]))
  end
end

-- Grey smoke for a rocket's exhaust trail: a slow, short-lived puff
-- drifting up behind the tail.
function Particles.smoke(ents, x, y)
  local cfg = config.particles
  for _ = 1, cfg.smoke_count do
    add(ents.particles, x, y, math.random() - 0.5, math.random()*0.5 - 0.75,
      cfg.smoke_colour, math.random(cfg.smoke_life[1], cfg.smoke_life[2]))
  end
end

-- A hot radial burst for a rocket detonation, alternating red/orange
-- (the flash ring itself is drawn from the booms list, not particles).
function Particles.boom(ents, x, y)
  local cfg = config.particles
  for i = 1, cfg.boom_count do
    local a   = math.random() * math.pi * 2
    local spd = math.random() * 3 + 1
    add(ents.particles, x, y, math.cos(a)*spd, math.sin(a)*spd,
      (i % 2 == 0) and cfg.boom_colour or 9,
      math.random(cfg.boom_life[1], cfg.boom_life[2]))
  end
end

-- Chunky debris shards for a heavy player hit: slabs of the player's
-- kit tearing off and tumbling away from the impact. Like the blood
-- spray they fly opposite the impact direction (`avx`/`avy`), with the
-- body's own motion carried (`bvx`/`bvy`) so the debris never lags a
-- moving target. Each shard is a random-sized chunk (2-4 px, drawn by
-- the renderer at its `s`) in a metal-and-cloth mix, chunkier and
-- longer-lived than the blood so the hit reads as set-piece carnage.
function Particles.shards(ents, x, y, avx, avy, bvx, bvy)
  local cfg = config.particles
  local len = math.sqrt(avx*avx + avy*avy)
  if len == 0 then len = 1 end
  local base = math.atan2(-avy/len, -avx/len)
  local cols = cfg.shard_colours
  for i = 1, cfg.shard_count do
    local a   = base + math.random()*0.9 - 0.45
    local spd = math.random() * 3.5 + 1
    add(ents.particles, x, y, math.cos(a)*spd + (bvx or 0),
      math.sin(a)*spd + (bvy or 0),
      cols[(i % #cols) + 1],
      math.random(cfg.shard_life[1], cfg.shard_life[2]),
      2 + math.floor(math.random() * 3))
  end
end

-- Scorched chunks knocked off LEVEL GEOMETRY when an enemy projectile
-- or a laser beam slams into terrain: dark grit with a few embers
-- riding along, sprayed back off the struck surface (opposite the
-- impact direction, like the blood spray). Deliberately NOT spawned by
-- the player's own arrows: their hits stay small and quiet against the
-- enemies' set-piece impacts.
function Particles.scorch(ents, x, y, avx, avy)
  local cfg = config.particles
  local len = math.sqrt(avx*avx + avy*avy)
  if len == 0 then len = 1 end
  local base = math.atan2(-avy/len, -avx/len)
  local cols = cfg.scorch_colours
  for i = 1, cfg.scorch_count do
    local a   = base + math.random()*1.1 - 0.55
    local spd = math.random() * 3.5 + 1
    add(ents.particles, x, y, math.cos(a)*spd, math.sin(a)*spd,
      cols[(i % #cols) + 1],
      math.random(cfg.scorch_life[1], cfg.scorch_life[2]),
      2 + math.floor(math.random() * 3))
  end
end

-- Advances the particles by `dt` steps of world time (1 normally;
-- reduced while aiming, so the spray slows with everything else).
-- `world` (optional) gates the pass to the active room: particles
-- beyond it hang frozen (off-screen) and resume on re-entry. A particle
-- carrying its own `g` overrides the shared gravity (the aftermath
-- smoke rises, so it carries a near-zero one).
function Particles.update(ents, dt, world)
  local list = ents.particles
  for i = #list, 1, -1 do
    local pt = list[i]
    if not world or world:in_room(pt.x, pt.y) then
      pt.x   = pt.x + pt.vx * dt
      pt.y   = pt.y + pt.vy * dt
      pt.vy  = pt.vy + (pt.g or config.particles.gravity) * dt
      pt.life = pt.life - dt
      if pt.life <= 0 then table.remove(list, i) end
    end
  end
end

-- ==== impact aftermath ====
--
-- A hit on level geometry leaves a short-lived BURNING SPOT: for a
-- second or so the burnt surface keeps spitting sparks off itself --
-- and, for blasts close to terrain, black smoke drifts up. These are
-- stand-ins for impact art, like the boom flash itself. Spots live in
-- ents.burns; nothing renders for the spot directly -- its emissions
-- are the visual.

-- Anchors a burning spot near (x, y) when level geometry sits within
-- reach of it: the eight surrounding directions are probed for the
-- nearest surface and the spot is pinned to that face, aimed off it.
-- `smoke` adds the rising black puffs (near-wall blasts). Nothing
-- anchors when there is no terrain nearby -- a blast in open air
-- leaves no burning remains.
function Particles.aftermath(ents, world, x, y, smoke)
  local cfg = config.particles
  local dx, dy, px, py
  for i = 0, 7 do
    local a = i / 8 * math.pi * 2
    local ux, uy = math.cos(a), math.sin(a)
    for d = 6, 24, 6 do
      if world:solid_for_arrow(x + ux*d, y + uy*d)
      or world:in_slope_solid(x + ux*d, y + uy*d) then
        px, py = x + ux*d, y + uy*d   -- the burnt face
        dx, dy = -ux, -uy             -- sparks fly back off it
        break
      end
    end
    if dx then break end
  end
  if not dx then return end
  table.insert(ents.burns, {
    x = px, y = py,
    dx = dx, dy = dy,   -- unit direction off the burnt surface
    t = cfg.aftermath_steps,
    spark_t = cfg.after_spark_every,
    smoke_t = cfg.after_smoke_every,
    smoke = smoke and true or nil,
  })
end

-- One sim step over the burning spots (world time = ctx.dt steps):
-- each ages out on its own, spitting spark flecks off the surface on a
-- jittered cadence and, for near-wall blasts, black smoke that rises.
-- Spots beyond the active room hang frozen like particles.
function Particles.update_burns(ents, dt, world)
  local cfg = config.particles
  local list = ents.burns
  for i = #list, 1, -1 do
    local s = list[i]
    if not world or world:in_room(s.x, s.y) then
      s.t = s.t - dt
      if s.t <= 0 then
        table.remove(list, i)
      else
        s.spark_t = s.spark_t - dt
        if s.spark_t <= 0 then
          s.spark_t = cfg.after_spark_every + math.random(0, 3)
          local base = math.atan2(s.dy, s.dx)
          for _ = 1, 2 do
            local a   = base + math.random()*0.7 - 0.35
            local spd = math.random() * 2.5 + 0.5
            add(ents.particles, s.x + s.dx*2, s.y + s.dy*2,
              math.cos(a)*spd, math.sin(a)*spd,
              (math.random() < 0.5) and cfg.spark_colour or 7,
              math.random(cfg.after_spark_life[1], cfg.after_spark_life[2]))
          end
        end
        if s.smoke then
          s.smoke_t = s.smoke_t - dt
          if s.smoke_t <= 0 then
            s.smoke_t = cfg.after_smoke_every + math.random(0, 4)
            -- black smoke drifting up from the burnt face (a near-zero
            -- gravity override keeps it rising for its whole life)
            add(ents.particles, s.x + math.random()*4 - 2,
              s.y + math.random()*4 - 2,
              math.random()*0.3 - 0.15, -(math.random()*0.35 + 0.25),
              (math.random() < 0.35) and 1 or 5,
              math.random(cfg.after_smoke_life[1], cfg.after_smoke_life[2]),
              2, cfg.after_smoke_g)
          end
        end
      end
    end
  end
end

return Particles
