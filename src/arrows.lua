-- Arrows: the player's arrows (flight, bounce, stick, key carrying,
-- switch/lock/enemy hits) and the enemies' arrows.
--
-- Player arrows act as one-tile-wide platforms when embedded in vertical
-- walls (see check_platforms), can carry keys to locks, and bounce off
-- sticky surfaces a limited number of times before spinning out.

local config = require("src.config")
local Util   = require("src.util")
local Particles    = require("src.particles")
local Interactables = require("src.interactables")

local Arrows = {}

-- Simulates an arrow's flight with the same integration the live enemy
-- arrows use, and returns sampled points. Used for the archer's ballistic
-- aim solving (clearance) and its aim-preview rendering.
--
-- opts:
--   step_px    px per substep sample (default 3)
--   max_frames simulated frames before giving up (default 60)
--   target     {x=, y=}: stop once within ~3px of this point
-- Returns { points = {...}, hit = bool, reached = bool }.
function Arrows.simulate_path(world, x, y, vx, vy, opts)
  opts = opts or {}
  local points = { {x = x, y = y} }
  local g = config.arrows.gravity
  local speed = math.sqrt(vx*vx + vy*vy)
  if speed <= 0 then
    return { points = points, hit = false, reached = false }
  end
  local nsub = math.max(1, math.ceil(speed / (opts.step_px or 3)))
  local sdt = 1 / nsub
  for _ = 1, (opts.max_frames or 60) do
    for _ = 1, nsub do
      local nx = x + vx * sdt
      local ny = y + vy * sdt + g * sdt * sdt / 2
      vy = vy + g * sdt
      x, y = nx, ny
      if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
        return { points = points, hit = true, reached = false }
      end
      local t = opts.target
      if t then
        local dx, dy = t.x - x, t.y - y
        if dx*dx + dy*dy <= 9 then
          return { points = points, hit = false, reached = true }
        end
      end
    end
    points[#points + 1] = { x = x, y = y }  -- one dot per simulated frame
  end
  return { points = points, hit = false, reached = false }
end

-- Releases a carried key back into the world (with a poof, as in twang.p8)
-- unless it was already consumed by a lock.
function Arrows.release(ctx, arrow)
  if arrow.key and not arrow.key.used then
    Particles.poof(ctx.ents, arrow.x, arrow.y)
    arrow.key.taken = false
  end
  arrow.key = nil
end

-- Fires an arrow from the player along `angle` (a pico-8 turn, 0..1) at
-- the player's current power level. `kind` selects the arrow type
-- ("normal" or "rope"). Evicts a stuck arrow to make room when the
-- quiver is full (releasing its key first, if any).
function Arrows.fire(ctx, angle, kind)
  local ents, p = ctx.ents, ctx.player
  local cfg = ctx.config.arrows
  kind = kind or "normal"
  -- firing a new rope arrow detaches any rope already attached, so the
  -- fresh anchor becomes the active one
  if kind == "rope" and p.rope then p.rope = nil end
  if #ents.arrows >= cfg.max_active then
    for i, a in ipairs(ents.arrows) do
      if a.stuck then
        if p.rope and p.rope.arrow == a then p.rope = nil end
        Arrows.release(ctx, a)
        table.remove(ents.arrows, i)
        break
      end
    end
    if #ents.arrows >= cfg.max_active then return end
  end
  local dx = Util.p8cos(angle)
  local dy = Util.p8sin(angle)
  local spd = cfg.speeds[p.aim_power]
  local arrow = {
    x = p.x + p.w/2, y = p.y + p.h/2,
    vx = dx*spd, vy = dy*spd,
    active = true, stuck = false, bounced = 0,
    sdx = dx, sdy = dy, spin = 0, lt = cfg.lifetime,
    kind = kind,
    traveled = 0,  -- rope arrows expire after config.rope.max_range of flight
  }
  -- a fired arrow takes the player's carried key along; the player can
  -- grab it back on contact once the short cooldown lapses (the arrow
  -- spawns inside the player, so without it the handoff would undo
  -- itself the same step). Rope arrows never carry keys.
  if p.key and kind ~= "rope" then
    arrow.key     = p.key
    arrow.grab_cd = cfg.grab_cooldown
    p.key = nil
  end
  table.insert(ents.arrows, arrow)
end

-- One 30hz step of a player arrow's flight. Stuck arrows only age.
function Arrows.step_one(ctx, a)
  local ents, world = ctx.ents, ctx.world
  local cfg = ctx.config.arrows
  local tw = ctx.config.tile_size
  local p0x, p0y  -- previous substep position (rope range tracking)

  if a.grab_cd and a.grab_cd > 0 then a.grab_cd = a.grab_cd - 1 end
  a.lt = a.lt - 1
  if a.lt <= 0 then a.active = false return end
  if a.stuck then return end

  -- out of bounces: keep flying and spinning briefly, then poof
  if a.dying then
    a.dying = a.dying - 1
    a.spin  = a.spin + cfg.spin_out_speed
    local nx, ny = a.x + a.vx, a.y + a.vy
    if a.dying <= 0 or world:solid_at(nx, ny) or world:in_slope_solid(nx, ny) then
      Particles.poof(ents, a.x, a.y)
      a.active = false
      return
    end
    a.x, a.y = nx, ny
    return
  end

  a.vy = a.vy + cfg.gravity
  -- substep the flight so fast arrows never skip a tile: collision and
  -- tip interactions are sampled every few pixels along the frame's path
  local nsub = math.max(1, math.ceil((math.abs(a.vx) + math.abs(a.vy)) / cfg.substep_pixels))
  local sx, sy = a.vx / nsub, a.vy / nsub
  for _ = 1, nsub do
    local nx = a.x + sx
    local ny = a.y + sy

    if world:in_slope_solid(nx, ny) then
      local spd = math.sqrt(a.vx*a.vx + a.vy*a.vy)
      a.sdx = spd > 0 and (a.vx/spd) or a.sdx
      a.sdy = spd > 0 and (a.vy/spd) or a.sdy
      a.x, a.y = nx, ny
      a.stuck, a.on_slope = true, true
      a.lt = cfg.stuck_lifetime
      if a.kind == "rope" then a.anchored = true end
      return
    end

    if world:solid_for_arrow(nx, ny) then
      local hx = world:solid_for_arrow(nx, a.y)
      local hy = world:solid_for_arrow(a.x, ny)
      local is_sticky = (hx and world:sticky_at(nx, a.y))
                     or (hy and world:sticky_at(a.x, ny))
                     or (not hx and not hy and world:sticky_at(nx, ny))
      if is_sticky then
        -- bounce: reflect velocity off the hit surface, conserving speed
        if hx then a.vx = -a.vx end
        if hy then a.vy = -a.vy end
        if not hx and not hy then a.vx, a.vy = -a.vx, -a.vy end
        a.bounced = a.bounced + 1
        if a.bounced > cfg.max_bounces then
          a.dying = cfg.spin_out_frames
          a.spin  = 0
        end
      else
        local spd = math.sqrt(a.vx*a.vx + a.vy*a.vy)
        a.sdx = spd > 0 and (a.vx/spd) or a.sdx
        a.sdy = spd > 0 and (a.vy/spd) or a.sdy
        a.stuck = true
        a.lt = cfg.stuck_lifetime
        if hx then
          -- stick with the tip AT the wall face, pulled a little further
          -- out, so the shaft and a carried key stay in the player's reach
          a.face = a.vx > 0 and math.floor(nx / tw) * tw
                           or (math.floor(nx / tw) + 1) * tw
          a.x = a.face - (a.vx > 0 and 3 or -3)
        else
          a.x = nx
        end
        if hy then
          a.y = (a.vy > 0) and (math.floor(ny / tw) * tw)
                            or ((math.floor(ny / tw) + 1) * tw)
        else
          a.y = ny
        end
        if a.kind == "rope" then
          -- the rope anchors here: the tip freezes at the wall face
          a.anchored = true
        end
        if not hx and a.key and not a.key.used then
          -- floor/ceiling hit: the key poofs back into the world
          Particles.poof(ents, a.x, a.y)
          a.key.taken = false
          a.key = nil
        end
      end
      return
    end

    -- rope arrows expire once they have flown their maximum range (a
    -- wall hit within range always sticks — the checks above return first)
    if a.kind == "rope" then
      local rdx, rdy = nx - (p0x or a.x), ny - (p0y or a.y)
      a.traveled = a.traveled + math.sqrt(rdx*rdx + rdy*rdy)
      p0x, p0y = nx, ny
      if a.traveled > ctx.config.rope.max_range then
        Particles.poof(ents, a.x, a.y)
        a.active = false
        return
      end
    end

    a.x, a.y = nx, ny

    -- key pickup by arrow tip (rope arrows never carry keys)
    if not a.key and a.kind ~= "rope" then
      for _, k in ipairs(ents.keys) do
        if not k.taken
        and nx >= k.x and nx < k.x+tw
        and ny >= k.y and ny < k.y+tw then
          a.key, k.taken = k, true
          break
        end
      end
    end

    -- arrow strikes a switch: toggle it and re-evaluate its group's doors
    -- (one toggle per pass through a switch's tile)
    local in_switch = false
    for _, s in ipairs(ents.switches) do
      if nx >= s.x and nx < s.x+tw and ny >= s.y and ny < s.y+tw then
        in_switch = true
        if a.last_switch ~= s then
          a.last_switch = s
          if not s.on then
            -- latching: one strike activates a switch permanently
            s.on = true
            Interactables.eval_switch_doors(ents, s.g)
            Interactables.trigger_springs(ents, ctx.player, s.g)
          end
        end
      end
    end
    if not in_switch then a.last_switch = nil end

    -- key-carrying arrow passes through a lock
    if a.key then
      for _, lock in ipairs(ents.locks) do
        if not lock.triggered
        and Interactables.key_fits_lock(a.key, lock)
        and nx >= lock.x and nx < lock.x+tw
        and ny >= lock.y and ny < lock.y+tw then
          Interactables.trigger_lock(ents, lock)
          a.key.used = true  -- consumed; will not respawn if arrow expires
          a.key      = nil
          break
        end
      end
    end

    -- enemy hit
    for i, e in ipairs(ents.enemies) do
      if nx >= e.x and nx < e.x+e.w and ny >= e.y and ny < e.y+e.h then
        Particles.blood(ents, nx, ny, a.vx, a.vy)
        table.remove(ents.enemies, i)
        a.active = false
        return
      end
    end

    if a.y < -10 or a.x < -10 or a.x > world.px_w or a.y > world.px_h then
      a.active = false
      return
    end
  end
end

-- One 30hz step over all player arrows. The list is read fresh each
-- iteration: a mid-loop player death resets it (the loop then ends early).
function Arrows.update(ctx)
  local ents, p = ctx.ents, ctx.player
  for i = #ents.arrows, 1, -1 do
    local a = ents.arrows[i]
    if not a then break end
    if not a.active then
      -- a removed anchored arrow releases the player's rope
      if p.rope and p.rope.arrow == a then p.rope = nil end
      Arrows.release(ctx, a)  -- poof the key back into the world if never consumed
      table.remove(ents.arrows, i)
    else
      Arrows.step_one(ctx, a)
    end
  end
end

-- Stuck arrows in vertical walls act as one-tile platforms.
function Arrows.check_platforms(ctx)
  local p, ents = ctx.player, ctx.ents
  local tw = ctx.config.tile_size
  if p.vy < 0 then return end
  for _, a in ipairs(ents.arrows) do
    if a.stuck and a.active and not a.on_slope and a.kind ~= "rope"
    and math.abs(a.sdx) >= math.abs(a.sdy) then
      -- only arrows embedded in vertical walls (horizontal travel) act
      -- as platforms; the wall face was recorded at stick time (the
      -- retracted tip no longer sits inside the wall tile)
      local ay = a.y
      local by = p.y + p.h
      if by >= ay - 1 and by <= ay + 4 then
        local ax1, ax2
        local wx = a.face
        if not wx then
          wx = a.sdx > 0 and math.floor(a.x/tw)*tw
                        or (math.floor(a.x/tw)+1)*tw
        end
        if a.sdx > 0 then
          ax1, ax2 = wx - 7, wx + 2
        else
          ax1, ax2 = wx - 2, wx + 7
        end
        if p.x + p.w > ax1 and p.x < ax2 then
          p.y  = ay - p.h
          p.vy = 0
          p.gr = true
          p.coy = ctx.config.player.coyote_frames
        end
      end
    end
  end
end

-- One 30hz step over all enemy arrows (simple ballistic darts). The list
-- is read fresh each iteration: a mid-loop player death resets it.
function Arrows.update_enemy_arrows(ctx)
  local ents, p, world = ctx.ents, ctx.player, ctx.world
  local cfg = ctx.config.arrows
  for i = #ents.e_arrows, 1, -1 do
    local a = ents.e_arrows[i]
    if not a then break end
    if not a.active then
      table.remove(ents.e_arrows, i)
    else
      a.vy = a.vy + cfg.gravity
      local nx = a.x + a.vx
      local ny = a.y + a.vy
      if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
        a.active = false
      else
        a.x, a.y = nx, ny
        if nx >= p.x and nx < p.x+p.w and ny >= p.y and ny < p.y+p.h then
          ctx.hurt(ctx)  -- one heart, unless shielded by i-frames
          a.active = false
        end
        if a.y < -10 or a.x < -10
        or a.x > world.px_w or a.y > world.px_h then
          a.active = false
        end
      end
    end
  end
end

return Arrows
