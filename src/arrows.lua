-- Arrows: the player's arrows (flight, bounce, stick, key carrying,
-- switch/lock/enemy hits) and the enemies' arrows.
--
-- Player arrows act as one-tile-wide platforms when embedded in vertical
-- walls (see check_platforms), can carry keys to locks, and bounce off
-- sticky surfaces a limited number of times before spinning out. Propel
-- arrows are harmless: they shove whatever they hit (enemies and the
-- player, bounce-backs included) along the arrow's impact vector.

local config = require("src.config")
local Util   = require("src.util")
local Particles    = require("src.particles")
local Interactables = require("src.interactables")
local WinchLog = require("src.winchlog")
local Rockets = require("src.rockets")
local Bombs = require("src.bombs")

local Arrows = {}

-- Simulates an arrow's flight with the same integration the live enemy
-- arrows use, and returns sampled points. Used for the archer's ballistic
-- aim solving (clearance) and its aim-preview rendering.
--
-- opts:
--   step_px    px per substep sample (default 6)
--   max_frames simulated frames before giving up (default 60)
--   target     {x=, y=}: stop once within ~6px of this point
-- Returns { points = {...}, hit = bool, reached = bool }.
function Arrows.simulate_path(world, x, y, vx, vy, opts)
  opts = opts or {}
  local points = { {x = x, y = y} }
  local g = config.arrows.gravity
  local speed = math.sqrt(vx*vx + vy*vy)
  if speed <= 0 then
    return { points = points, hit = false, reached = false }
  end
  local nsub = math.max(1, math.ceil(speed / (opts.step_px or 6)))
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
        if dx*dx + dy*dy <= 36 then
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
-- the player's current power level, scaled by `force` (analog stick
-- tilt: 1 = the power level's full launch speed, so full tilt keeps the
-- maximum). `kind` selects the arrow type ("normal" or "rope"). Evicts
-- a stuck arrow to make room when the quiver is full (releasing its key
-- first, if any).
function Arrows.fire(ctx, angle, kind, force)
  local ents, p = ctx.ents, ctx.player
  local cfg = ctx.config.arrows
  kind = kind or "normal"
  -- firing any arrow cancels a winch reel in progress (the player's
  -- escape hatch from the unstoppable pull); the leftover reel momentum
  -- gets the grace window too, so it plays out untouched
  if p.winch then
    p.winch = nil
    p.winch_grace = config.winch.stick_grace
    p.rope_cd = config.winch.stick_grace
  end
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
  local spd = cfg.speeds[p.aim_power] * (force or 1)
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

  -- firing a propel arrow cuts an attached rope (it is a mobility tool;
  -- the shove itself happens on impact, not on fire)
  if kind == "propel" and p.rope then p.rope = nil end
end

-- One sim step of a player arrow's flight (world time = ctx.dt steps).
-- Stuck arrows only age.
function Arrows.step_one(ctx, a)
  local ents, world = ctx.ents, ctx.world
  local cfg = ctx.config.arrows
  local tw = ctx.config.tile_size
  local dt = ctx.dt
  local p0x, p0y  -- previous substep position (rope range tracking)

  if a.grab_cd and a.grab_cd > 0 then
    a.grab_cd = math.max(0, a.grab_cd - dt)
  end
  a.lt = a.lt - dt
  if a.lt <= 0 then a.active = false return end
  if a.stuck then return end

  -- out of bounces: keep flying and spinning briefly, then poof
  if a.dying then
    a.dying = a.dying - dt
    a.spin  = a.spin + cfg.spin_out_speed * dt
    local nx, ny = a.x + a.vx * dt, a.y + a.vy * dt
    if a.dying <= 0 or world:solid_at(nx, ny) or world:in_slope_solid(nx, ny) then
      Particles.poof(ents, a.x, a.y)
      a.active = false
      return
    end
    a.x, a.y = nx, ny
    return
  end

  a.vy = a.vy + cfg.gravity * dt
  -- substep the flight so fast arrows never skip a tile: collision and
  -- tip interactions are sampled every few pixels along the step's path
  local nsub = math.max(1,
    math.ceil((math.abs(a.vx) + math.abs(a.vy)) * dt / cfg.substep_pixels))
  local sx, sy = a.vx * dt / nsub, a.vy * dt / nsub
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
          a.x = a.face - (a.vx > 0 and 6 or -6)
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

    -- key pickup by arrow tip (rope arrows never carry keys); the pad
    -- grows the key's tile so a near-miss still snags it
    if not a.key and a.kind ~= "rope" then
      local pad = config.keys.pickup_pad
      for _, k in ipairs(ents.keys) do
        if not k.taken
        and nx >= k.x-pad and nx < k.x+tw+pad
        and ny >= k.y-pad and ny < k.y+tw+pad then
          a.key, k.taken = k, true
          break
        end
      end
    end

    -- rope arrow strikes a winch: the "arrow" is gone but the winch has
    -- it - the player is pulled in immediately, reeled through the
    -- centre and thrown out the far side (see Player.physics)
    if a.kind == "rope" and not ctx.player.winch then
      local pad = config.winch.hit_pad
      for _, w in ipairs(ents.winches) do
        if nx >= w.x-pad and nx < w.x+tw+pad
        and ny >= w.y-pad and ny < w.y+tw+pad then
          local p = ctx.player
          p.rope = nil      -- a winch replaces any rope, and the rope_cd
          p.rope_cd = 0     -- grace: the pull is immediate
          -- the throw direction is carried from the entry side: the
          -- unit vector toward the winch now, refreshed by the reel
          -- while the player is still outside the pass radius, so an
          -- overshoot past the centre can never invert the throw
          local wcx, wcy = w.x + tw/2, w.y + tw/2
          local edx, edy = wcx - p.x - p.w/2, wcy - p.y - p.h/2
          local d = math.sqrt(edx*edx + edy*edy)
          if d > 0 then
            edx, edy = edx / d, edy / d
          else
            edx, edy = a.sdx or 0, a.sdy or 0  -- degenerate: arrow travel
          end
          p.winch = { ent = w, dir_x = edx, dir_y = edy }
          if WinchLog.on() then
            WinchLog.log("capture", {
              step = ctx.menu and ctx.menu.step_count or 0,
              tip_x = nx, tip_y = ny,
              winch_x = w.x, winch_y = w.y,
              player_x = p.x, player_y = p.y,
              vx = p.vx, vy = p.vy,
              dist = d, entry_dx = edx, entry_dy = edy,
            })
          end
          Particles.poof(ents, nx, ny)
          a.active = false
          return
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
          -- every strike flips the switch: springs fire when it turns
          -- on, doors re-evaluate either way; only switches flagged
          -- "phase" flip the level's phase tiles, so a spring switch
          -- never dissolves the blocks (and vice versa)
          s.on = not s.on
          Interactables.eval_switch_doors(ents, s.g)
          if s.on then
            Interactables.trigger_springs(ents, ctx.player, s.g)
          end
          if s.phase then
            Interactables.toggle_phase_tiles(ctx.world)
          end
        end
      end
    end
    if not in_switch then a.last_switch = nil end

    -- key-carrying arrow passes through a lock (padded tile: the key
    -- triggers on a near pass, not just a direct hit)
    if a.key then
      local pad = config.keys.lock_pad
      for _, lock in ipairs(ents.locks) do
        if not lock.triggered
        and Interactables.key_fits_lock(a.key, lock)
        and nx >= lock.x-pad and nx < lock.x+tw+pad
        and ny >= lock.y-pad and ny < lock.y+tw+pad then
          Interactables.trigger_lock(ents, lock)
          a.key.used = true  -- consumed; will not respawn if arrow expires
          a.key      = nil
          break
        end
      end
    end

    -- propel arrows shove whatever they hit along the arrow's impact
    -- vector (an added impulse), player included: the tip must first
    -- have left the player's box, so a bounced-back arrow can fling the
    -- shooter while a freshly fired one cannot hit at spawn
    if a.kind == "propel" then
      local p = ctx.player
      if nx >= p.x and nx < p.x+p.w and ny >= p.y and ny < p.y+p.h then
        if a.player_clear then
          p.vx, p.vy = p.vx + a.vx, p.vy + a.vy
          if p.vy < 0 then
            p.gr = false
            p.j_frames = 0
          end
          Particles.poof(ents, a.x, a.y)
          a.active = false
          return
        end
      else
        a.player_clear = true
      end
    end

    -- enemy hit: propel arrows shove the enemy instead of killing it
    for i, e in ipairs(ents.enemies) do
      if nx >= e.x and nx < e.x+e.w and ny >= e.y and ny < e.y+e.h then
        if a.kind == "propel" then
          e.vx, e.vy = e.vx + a.vx, e.vy + a.vy
          if e.vy < 0 then e.gr = false end
          Particles.poof(ents, a.x, a.y)
        else
          Particles.blood(ents, nx, ny, a.vx, a.vy)
          table.remove(ents.enemies, i)
        end
        a.active = false
        return
      end
    end

    -- rocket hit: any arrow tip (propel included) detonates the rocket
    -- where it hangs -- the arrow is consumed by the blast, like an
    -- enemy hit consumes it. The hitbox is generous (config-sized box
    -- around the centre) so a near miss still counts.
    local hw = ctx.config.enemies.rocket_hit_w
    local hh = ctx.config.enemies.rocket_hit_h
    for _, r in ipairs(ents.rockets) do
      if r.active
      and nx >= r.x - hw/2 and nx < r.x + hw/2
      and ny >= r.y - hh/2 and ny < r.y + hh/2 then
        Rockets.explode(ctx, r.x, r.y)
        r.active = false
        a.active = false
        return
      end
    end

    -- bomb hit: any arrow tip (propel included) detonates the thrown
    -- bomb in flight too, through the same generous hitbox and shared
    -- blast (the arrow is consumed either way)
    local bw = ctx.config.enemies.bomb_hit_w
    local bh = ctx.config.enemies.bomb_hit_h
    for _, b in ipairs(ents.bombs) do
      if b.active
      and nx >= b.x - bw/2 and nx < b.x + bw/2
      and ny >= b.y - bh/2 and ny < b.y + bh/2 then
        Bombs.explode(ctx, b.x, b.y)
        b.active = false
        a.active = false
        return
      end
    end

    if a.y < -20 or a.x < -20 or a.x > world.px_w or a.y > world.px_h then
      a.active = false
      return
    end
  end
end

-- One sim step over all player arrows (world time = ctx.dt steps). The
-- list is read fresh each iteration: a mid-loop player death resets it
-- (the loop then ends early).
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
      if by >= ay - 2 and by <= ay + 8 then
        local ax1, ax2
        local wx = a.face
        if not wx then
          wx = a.sdx > 0 and math.floor(a.x/tw)*tw
                        or (math.floor(a.x/tw)+1)*tw
        end
        if a.sdx > 0 then
          ax1, ax2 = wx - 14, wx + 4
        else
          ax1, ax2 = wx - 4, wx + 14
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

-- One sim step over all enemy arrows (simple ballistic darts; world
-- time = ctx.dt steps). The list is read fresh each iteration: a
-- mid-loop player death resets it.
-- Flight is substepped like the player's arrows: a dart moves up to
-- ~16.5px per step and the player's box is only 8px wide, so a single
-- endpoint check would let fast arrows tunnel straight through. A hit
-- arrow rests at the impact point for player_stick_frames before
-- vanishing (the hit is felt, not just guessed at from blood).
function Arrows.update_enemy_arrows(ctx)
  local ents, p, world = ctx.ents, ctx.player, ctx.world
  local cfg = ctx.config.arrows
  local dt = ctx.dt
  for i = #ents.e_arrows, 1, -1 do
    local a = ents.e_arrows[i]
    if not a then break end
    if not a.active then
      table.remove(ents.e_arrows, i)
    elseif a.hit_stick then
      -- frozen at the player-impact point: no motion, no collisions
      a.hit_stick = a.hit_stick - dt
      if a.hit_stick <= 0 then table.remove(ents.e_arrows, i) end
    else
      a.vy = a.vy + cfg.gravity * dt
      local nsub = math.max(1,
        math.ceil((math.abs(a.vx) + math.abs(a.vy)) * dt / cfg.substep_pixels))
      local sx, sy = a.vx * dt / nsub, a.vy * dt / nsub
      for _ = 1, nsub do
        local nx = a.x + sx
        local ny = a.y + sy
        if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
          a.active = false
          break
        end
        a.x, a.y = nx, ny
        if nx >= p.x and nx < p.x+p.w and ny >= p.y and ny < p.y+p.h then
          ctx.hurt(ctx, a.vx, a.vy)  -- one heart, unless shielded by i-frames
          a.hit_stick = cfg.player_stick_frames
          break
        end
        if a.y < -20 or a.x < -20
        or a.x > world.px_w or a.y > world.px_h then
          a.active = false
          break
        end
      end
    end
  end
end

return Arrows
