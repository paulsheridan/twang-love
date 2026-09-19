-- Particles: poofs (key releases, deaths, arrow expiry), blood and
-- laser-impact sparks.
--
-- Particles are simple world-space dots with velocity and a step lifetime.

local config = require("src.config")

local Particles = {}

local function add(list, x, y, vx, vy, col, life)
  table.insert(list, {x = x, y = y, vx = vx, vy = vy, col = col, life = life})
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

-- Advances the particles by `dt` steps of world time (1 normally;
-- reduced while aiming, so the spray slows with everything else).
function Particles.update(ents, dt)
  local list = ents.particles
  for i = #list, 1, -1 do
    local pt = list[i]
    pt.x   = pt.x + pt.vx * dt
    pt.y   = pt.y + pt.vy * dt
    pt.vy  = pt.vy + config.particles.gravity * dt
    pt.life = pt.life - dt
    if pt.life <= 0 then table.remove(list, i) end
  end
end

return Particles
