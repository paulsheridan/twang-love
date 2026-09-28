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

--- Linear interpolation.
function Util.lerp(a, b, t)
  return a + (b - a) * t
end

--- The rendered position of a movable between its previous and current
--- sim positions (`alpha` = the frame's unfinished-time fraction,
--- accumulator over step length). Falls back to the live position when
--- no previous was stamped (the thing spawned this tick).
function Util.render_pos(e, alpha)
  if e._px then
    return e._px + (e.x - e._px) * alpha, e._py + (e.y - e._py) * alpha
  end
  return e.x, e.y
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

--- Clamps a PICO-8 aim turn to the 180 degrees pointing AWAY from a
--- wall on the body's side (`side` 1 = right wall, -1 = left wall).
--- Aim turn 0 = right, 0.25 = down, 0.5 = left, 0.75 = up. The away
--- half for a right wall is 0.25..0.75 (down through left to up); for
--- a left wall it is 0.75..1.25 -- up through right to down, the
--- complementary half. Angles already inside the half pass unchanged;
--- anything else snaps to the NEARER edge anchor (circular distance),
--- preferring the up anchor (0.75) on a tie so the clamp never points
--- into the ground out of nowhere.
function Util.clamp_aim_away(turn, side)
  local t = ((turn % 1) + 1) % 1
  local inside
  if side >= 0 then
    inside = t > 0.25 and t < 0.75
  else
    inside = t >= 0.75 or t <= 0.25
  end
  if inside then return t end
  local function cd(a, b)
    local d = math.abs(a - b)
    if d > 0.5 then d = 1 - d end
    return d
  end
  local d_up   = cd(t, 0.75)
  local d_down = cd(t, 0.25)
  return d_up <= d_down and 0.75 or 0.25
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
