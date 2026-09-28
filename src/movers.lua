-- Moving blocks: tile-aligned platforms that travel back and forth along
-- a line (placed as "mover" objects in Tiled; scanned in src/level.lua),
-- pausing momentarily at each end of that line.
--
--   auto ("mover"): cycles forever — [pause at the A end] -> go ->
--   pause at the B end -> back -> pause -> on and on.
--   trigger ("mover_trigger"): waits parked at rest until the player
--   LANDS on it (a rising edge: standing when it fired, then jumping
--   off and landing again, is what re-arms it — a rider who never
--   leaves keeps it parked) or until a player arrow strikes it (the
--   tip entering any tile of the block consumes the arrow like a
--   pusher strike), then runs the line to the far end, pauses and
--   returns on its own to the rest position, where it parks again.
--
-- The player standing on the top face rides (carried in carry below);
-- anything SOLID in the block's next position (terrain, doors, another
-- mover) STALLS it for the step rather than being met halfway — and a
-- body (player or enemy) in the path does the same, so nothing gets
-- crushed; the block waits for the way to clear.
--
-- World time: everything scales by ctx.dt, so the movers ride aiming's
-- slow motion like every other system. Off-room movers freeze
-- (in_room), matching the springs.

local config = require("src.config")

local Movers = {}

-- The ride: a rider's feet y must sit in the top-face band grown by the
-- ride margin (riders trail the face slightly before the ride breaks),
-- and their FOOT SPAN must still overlap the block's EXACT box. The
-- solidity is pixel-exact too (World:mover_at), so the ride holds
-- while any foot corner pixel is over the block — the footing rule
-- matches resolve_y's two-corner stand exactly: hanging a toe over the
-- edge holds, walking fully off does not, and the two can never
-- disagree (they did when solidity was tile-granular: a moving face
-- sits mid-tile and the half-covered edge tile supported a stand the
-- exact-span ride could not see — edge-standers froze the block).
local function feet_on(m, p)
  local feet_y = p.y + p.h
  local margin = config.mover.ride_margin
  if feet_y < m.by - margin or feet_y > m.by + 2 then
    return false
  end
  return p.x + p.w > m.bx and p.x < m.bx + m.bw
end

local function rect_overlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
  return ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1
end

-- Is any tile of the box at (x, y) solid to a BODY? Doors, pushers,
-- spring pads, terrain and OTHER MOVERS all count (a mover also
-- refuses to step onto another's box, so sibling lifts can share a
-- shaft without trying to occupy the same pixels). The mover's own
-- current tiles are skipped (skip_mover) — they are solid to the world
-- but obviously not to itself.
local function box_blocked(world, m, x, y, w, h)
  local x2, y2 = x + w - 1, y + h - 1
  local probes = { {x, y}, {x2, y}, {x, y2}, {x2, y2},
                   {x + w/2, y}, {x + w/2, y2}, {x, y + h/2}, {x2, y + h/2} }
  for _, pt in ipairs(probes) do
    if world:solid_at(pt[1], pt[2], m) then
      return true
    end
  end
  return false
end

-- Would anything solid sit in the block's box after moving by (dx, dy)?
local function path_blocked(ctx, m, dx, dy)
  local world = ctx.world
  local mx, my = m.bx + dx, m.by + dy
  for _, o in ipairs(world.movers) do
    if o ~= m and rect_overlap(mx, my, mx + m.bw, my + m.bh,
                               o.bx, o.by, o.bx + o.bw, o.by + o.bh) then
      return true
    end
  end
  return box_blocked(world, m, mx, my, m.bw, m.bh)
end

-- Would a body (player or enemy, box-grown by pad px) sit in the
-- block's path after moving? Riders on the CURRENT top face are exempt
-- (they move WITH the block, carried after the step); anything else --
-- a player under a lowering lift, an enemy walking into the way --
-- STALLS it. No crush: the block waits for the way to clear.
local function body_tangle(ctx, m, dx, dy)
  local nx, ny = m.bx + dx, m.by + dy
  local pad = 2
  local p = ctx.player
  if not (p.ride == m)
  and rect_overlap(nx - pad, ny - pad, nx + m.bw + pad, ny + m.bh + pad,
                   p.x, p.y, p.x + p.w, p.y + p.h) then
    return true
  end
  if ctx.config.enemies.enabled then
    for _, e in ipairs(ctx.ents.enemies) do
      if rect_overlap(nx - pad, ny - pad, nx + m.bw + pad, ny + m.bh + pad,
                      e.x, e.y, e.x + e.w, e.y + e.h) then
        return true
      end
    end
  end
  return false
end

-- One sim step of ONE mover (world time dt). Whole-pixel motion: the
-- speed accumulates fractionally and the block advances whole px.
local function step_one(ctx, m, dt)
  local cfg = config.mover
  local pause_steps = m.pause_steps or cfg.pause_steps

  if m.state == "rest" then
    -- an auto mover cycles away at once; a trigger waits for its rider
    m.vel = 0
    if m.mode == "auto" then
      m.state, m.t = "go", 0
      m.was_on = nil
    end
    return
  end

  if m.state == "pause" then
    m.vel = 0
    m.t = m.t + dt
    if m.t >= pause_steps then
      if m.mode == "trigger" and m.px <= 0 and m.dirn < 0 then
        -- home again after a return trip: park and re-arm in place
        m.state, m.t, m.f = "rest", 0, 0
        m.dirn = 1
        return
      end
      -- the far end (or the home end of an auto): run back the other way
      m.dirn = -m.dirn
      m.state, m.t = "go", 0
    end
    return
  end

  -- "go": advance along the line
  m.f = m.f + (m.speed or cfg.speed) * dt
  local steps = math.floor(m.f)
  if steps <= 0 then return end
  -- clamp the advance at the line's ends (never overshoot the pause)
  local room = m.dirn > 0 and (m.len - m.px) or m.px
  if room <= 0 then
    m.state, m.t = "pause", 0
    m.vel = 0
    return
  end
  if steps > room then
    -- run only as far as the end; any banked remainder beyond it is
    -- dropped (the pause timer starts from the arrival step)
    steps = room
    m.f = 0
  end

  local dx = m.dx * steps
  local dy = m.dy * steps
  if path_blocked(ctx, m, dx, dy) or body_tangle(ctx, m, dx, dy) then
    -- stalled: the block waits; the banked step is DROPPED (the stall
    -- wastes it), so the bank never grows past one step's worth and
    -- nothing teleports through the way when it clears. Its live
    -- velocity reads zero while it waits.
    m.f = m.f % 1
    m.vel = 0
    m.stall_t = (m.stall_t or 0) + dt
    return
  end
  m.f = m.f - steps

  m.px = m.px + m.dirn * steps
  m.bx = m.ox + m.dx * m.px
  m.by = m.oy + m.dy * m.px
  m.moved_dx, m.moved_dy = dx, dy
  m.vel = m.dx * m.dirn * (m.speed or cfg.speed)
  m.stall_t = nil
  if m.px == 0 or m.px == m.len then
    -- an end reached: momentarily pause (the same at both ends)
    m.state, m.t = "pause", 0
  end
end

-- Step the whole mover system (one sim step; ctx.dt world-time steps).
function Movers.update(ctx)
  local dt = ctx.dt or 1
  local world = ctx.world

  -- ride bind: the player standing on a top-face band (only the player
  -- rides in v1; enemies would wreck their patrol logic on lifts).
  -- A rider who JUMPS (vy < 0) severs the ride. When the ride severs
  -- while the block is actually moving, the rider INHERITS the block's
  -- velocity (their walk-off / jump carries the platform's motion the
  -- way normal ground's inertia does: jumping straight up from a
  -- moving block lands you back on it, not behind it).
  for _, m in ipairs(ctx.ents.movers) do
    if world:in_room(m.bx + m.bw / 2, m.by + m.bh / 2) then
      local p = ctx.player
      if p.vy >= 0 and feet_on(m, p) then
        p.ride = m
      elseif p.ride == m then
        p.ride = nil
        if m.vel and m.dx ~= 0 then
          p.vx = p.vx + m.vel
        end
      end
      step_one(ctx, m, dt)
    end
    -- off-room movers freeze exactly where they sit
  end

  -- carry after moving: riders ride the block's motion (the block may
  -- have advanced a few px this step in either axis). The follow is
  -- purely RELATIVE — the rider keeps whatever offset they had over the
  -- block, and the next physics pass re-lands their feet exactly on the
  -- face via mover_stand_y — so a falling rider caught inside the band
  -- drifts down onto the face naturally instead of being yanked to it.
  for _, m in ipairs(ctx.ents.movers) do
    if m.moved_dx then
      local p = ctx.player
      if p.ride == m then
        local dx, dy = m.moved_dx, m.moved_dy
        if dy ~= 0 then
          -- vertical rides press/pull the rider with the face (a lift
          -- rising pushes from below, lowering drags the feet down)
          p.y = p.y + dy
          p.vy = 0
          p.gr = true
        end
        if dx ~= 0 then
          p.x = p.x + dx
          -- dragged into a wall beside the line: clamp out of it (the
          -- block keeps running; the rider drops off when the ride
          -- band breaks). The ridden block itself is skipped in the
          -- probes (skip_mover): a rider whose feet sit a px or two
          -- inside the top face must never read it as a wall -- that
          -- would tile-snap them sideways off the platform
          local world_ = ctx.world
          if dx > 0 and (world_:solid_at(p.x + p.w - 1, p.y, m)
          or world_:solid_at(p.x + p.w - 1, p.y + p.h - 1, m)) then
            p.x = math.floor((p.x + p.w - 1) / world_.tw) * world_.tw - p.w
          elseif dx < 0 and (world_:solid_at(p.x, p.y, m)
          or world_:solid_at(p.x, p.y + p.h - 1, m)) then
            p.x = (math.floor(p.x / world_.tw) + 1) * world_.tw
          end
        end
      end
      m.moved_dx, m.moved_dy = nil, nil
    end
  end

  -- triggers: a parked trigger mover fires on a fresh LANDING on its
  -- top face (feet on the block + grounded). The edge reads "the feet
  -- are on the block" for the RE-ARM (only feet that LEFT the block arm
  -- it again) and "grounded on it" for the FIRE, so a rider who stays
  -- over the block — even briefly airborne above it — never re-fires,
  -- while a genuine landing from outside does (stays parked by design).
  for _, m in ipairs(ctx.ents.movers) do
    if m.mode == "trigger" and m.state == "rest" then
      local p = ctx.player
      local on = feet_on(m, p)
      if not on then
        m.was_on = false          -- the feet left the block
      elseif p.gr and not m.was_on then
        m.state, m.t = "go", 0    -- a fresh landing on it
        m.was_on = true
      end
    end
  end
end

-- An arrow tip struck the block (called from src/arrows.lua each
-- substep; the caller consumes the arrow like a pusher strike).
function Movers.trigger(ctx, m)
  if m.mode ~= "trigger" or m.state ~= "rest" then return end
  m.state, m.t = "go", 0
end

return Movers
