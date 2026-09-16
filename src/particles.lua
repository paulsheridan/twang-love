-- Particles: poofs (key releases, deaths, arrow expiry) and blood.
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

function Particles.update(ents)
  local list = ents.particles
  for i = #list, 1, -1 do
    local pt = list[i]
    pt.x   = pt.x + pt.vx
    pt.y   = pt.y + pt.vy
    pt.vy  = pt.vy + config.particles.gravity
    pt.life = pt.life - 1
    if pt.life <= 0 then table.remove(list, i) end
  end
end

return Particles
