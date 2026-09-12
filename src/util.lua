-- Small math and geometry helpers shared across the game.

local Util = {}

Util.TAU = math.pi * 2

--- Clamps `value` to the closed interval [low, high].
function Util.clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

--- Steps `value` toward `target` by at most `step`, never overshooting.
function Util.move_toward(value, target, step)
  if value < target then
    return math.min(value + step, target)
  end
  return math.max(value - step, target)
end

-- Aim angles follow the PICO-8 convention: a full turn is 1.0 (range
-- 0..1), with 0 = right, 0.25 = down, 0.5 = left and 0.75 = up. The
-- p8sin/p8cos helpers convert such a turn to radians for the standard
-- math functions.

function Util.p8sin(turn)
  return math.sin(turn * Util.TAU)
end

function Util.p8cos(turn)
  return math.cos(turn * Util.TAU)
end

--- Converts a direction vector to a PICO-8 turn (0..1).
function Util.turn_from_direction(dx, dy)
  return (math.atan2(dy, dx) / Util.TAU) % 1
end

--- True when two axis-aligned boxes ({x, y, width, height}) overlap.
function Util.boxes_overlap(a, b)
  return a.x < b.x + b.width and a.x + a.width > b.x
     and a.y < b.y + b.height and a.y + a.height > b.y
end

--- True when two game entities ({x, y, w, h}) overlap.
function Util.aabb(a, b)
  return a.x < b.x + b.w and a.x + a.w > b.x
     and a.y < b.y + b.h and a.y + a.h > b.y
end

return Util
