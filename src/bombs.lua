-- Bombs: the bomber's thrown explosives. A throw flies in a straight
-- line (no gravity, no steering) at where the player stood when the
-- telegraph lapsed, carrying the fuse time the thrower picked: a cheap,
-- deliberately rough guess (straight-line distance over throw speed,
-- jittered) rather than a solved shot. In flight the bomb acts like
-- flak around an airborne player -- proximity to their live centre
-- bursts it early -- and like a grenade over one on the ground: the
-- timer alone detonates it, the body bounces off terrain with damping
-- instead. Either way a player arrow tip detonates it, through the
-- same shared blast the rockets use.

local config = require("src.config")
local Rockets = require("src.rockets")

local Bombs = {}

-- Detonates at (x, y) through the shared blast (flash ring, spark
-- burst, poof, damage to the player caught in it, instant removal of
-- any enemy in the radius).
function Bombs.explode(ctx, x, y)
  local cfg = ctx.config.enemies
  Rockets.blast(ctx, x, y, cfg.bomb_blast_radius, cfg.bomb_half_hearts)
end

-- Spawns a bomb at (x, y) flying straight along (vx, vy) with the
-- thrower's fuse (world-time steps). The global airborne cap
-- (bomb_max_alive) drops excess throws.
function Bombs.spawn(ctx, x, y, vx, vy, fuse)
  local cfg = ctx.config.enemies
  if #ctx.ents.bombs >= cfg.bomb_max_alive then return nil end
  local b = {
    x = x, y = y,
    vx = vx, vy = vy,
    fuse = fuse,
    active = true,
  }
  table.insert(ctx.ents.bombs, b)
  return b
end

-- One sim step of a bomb in flight (world time = ctx.dt steps):
--
--   * the fuse burns wherever the bomb is -- this is the grenade's
--     burst (and every bomb's last resort, flak included)
--   * flak: while the player is airborne, proximity to their live
--     centre bursts the bomb early (air-burst on a jump)
--   * straight-line flight, substepped so a fast throw never skips a
--     tile; terrain contact bounces the grenade body with damping
--     (a slow bounce rests it where it lies, fuse still burning)
local function step_bomb(ctx, b)
  local cfg = ctx.config.enemies
  local p, world = ctx.player, ctx.world

  b.fuse = b.fuse - ctx.dt
  if b.fuse <= 0 then
    Bombs.explode(ctx, b.x, b.y)
    b.active = false
    return
  end

  if not p.gr then
    local dx, dy = p.x + p.w/2 - b.x, p.y + p.h/2 - b.y
    if dx*dx + dy*dy <= cfg.bomb_flak_proximity * cfg.bomb_flak_proximity then
      Bombs.explode(ctx, b.x, b.y)
      b.active = false
      return
    end
  end

  local move = math.sqrt(b.vx*b.vx + b.vy*b.vy) * ctx.dt
  if move > 0 then
    local nsub = math.max(1, math.ceil(move / cfg.bomb_substep))
    local sx, sy = b.vx * ctx.dt / nsub, b.vy * ctx.dt / nsub
    for _ = 1, nsub do
      local nx, ny = b.x + sx, b.y + sy
      if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
        -- grenade body: bounce, don't detonate (axis-separated checks,
        -- like the arrow bounce; a corner reverses both axes) -- then
        -- spend the rest of the step at the last free spot
        local hx = world:solid_for_arrow(nx, b.y) or world:in_slope_solid(nx, b.y)
        local hy = world:solid_for_arrow(b.x, ny) or world:in_slope_solid(b.x, ny)
        if hx then b.vx = -b.vx end
        if hy then b.vy = -b.vy end
        if not hx and not hy then b.vx, b.vy = -b.vx, -b.vy end
        b.vx = b.vx * cfg.bomb_bounce_damp
        b.vy = b.vy * cfg.bomb_bounce_damp
        if math.sqrt(b.vx*b.vx + b.vy*b.vy) < cfg.bomb_rest_speed then
          b.vx, b.vy = 0, 0
        end
        break
      end
      b.x, b.y = nx, ny
    end
  end

  if b.x < -20 or b.y < -20
  or b.x > world.px_w or b.y > world.px_h then
    b.active = false
  end
end

-- One sim step over all bombs in flight (world time = ctx.dt steps).
-- The list is read fresh each iteration: a mid-loop player death resets
-- it (the loop then ends early).
function Bombs.update(ctx)
  local ents = ctx.ents
  for i = #ents.bombs, 1, -1 do
    local b = ents.bombs[i]
    if not b then break end
    if not b.active then
      table.remove(ents.bombs, i)
    elseif ctx.world:in_room(b.x, b.y) then
      step_bomb(ctx, b)
      if not b.active then table.remove(ents.bombs, i) end
    end  -- bombs beyond the active room hang frozen (off-screen)
  end
end

return Bombs
