-- The player: state, respawn, 30hz physics (with coyote time and jump
-- buffering), bow aiming/firing, and key carrying.

local config = require("src.config")
local Util   = require("src.util")

local Camera       = require("src.camera")
local Particles    = require("src.particles")
local Interactables = require("src.interactables")
local Arrows       = require("src.arrows")

local Player = {}

-- Run cycle state (advances at the 30hz sim rate; twang.p8 advanced it in
-- _draw at 30fps). Deliberately not reset on respawn, like the original.
local run_frame, run_tick = 0, 0

--- Builds a fresh player at `spawn` ({x=, y=} or nil for the cart default).
function Player.new(spawn)
  local cfg = config.player
  local p = {
    x = spawn and spawn.x or 4,
    y = spawn and spawn.y or 82,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, coy = 0, jbuf = 0, fr = 1.0,
    j_frames = 0,
    wall_l = false, wall_r = false,
    aim_angle = 0, aim_power = config.aiming.start_power,
    was_aiming = false, aimed_down = false,
    prev_gr = false, land_frames = 0,
    key = nil,  -- carried key object (taken from the world or an arrow)
    hp = config.player.hearts * 2,   -- health in half-hearts (drawn top-left)
    invuln = 0,  -- post-hit invulnerability steps remaining
    arrow_kind = "normal",  -- currently selected arrow type ("normal"/"rope")
    rope = nil,  -- attached rope: { arrow = <anchored rope arrow>, length = px }
    rope_cd = 0, -- steps before another rope can attach (post-detach grace)
  }
  return p
end

-- Respawns: re-places the player at a random spawn point (reusing the
-- table so references stay valid).
function Player.reset(p, spawn_points, cam, world)
  local sp = spawn_points[math.random(#spawn_points)]
  p.x = sp and sp.x or 4
  p.y = sp and sp.y or 82
  p.vx = 0
  p.vy = 0
  p.w = config.player.width
  p.h = config.player.height
  p.gr = false
  p.facing = 1
  p.coy = 0
  p.jbuf = 0
  p.fr = 1.0
  p.j_frames = 0
  p.wall_l = false
  p.wall_r = false
  p.aim_angle = 0
  p.aim_power = config.aiming.start_power
  p.was_aiming = false
  p.aimed_down = false
  p.prev_gr = false
  p.land_frames = 0
  p.key = nil
  p.hp = config.player.hearts * 2
  p.invuln = 0
  p.arrow_kind = "normal"
  p.rope = nil
  p.rope_cd = 0
  -- snap camera to the spawn point (pico-8 snapped per screen; no slow pan)
  if cam then
    Camera.snap(cam, p, world)
  end
end

-- Death: a carried (unconsumed) key drops back into the world where the
-- player fell, then respawn; arrows in flight are cleared (so any rope
-- attachment goes with them).
function Player.die(ctx)
  local p = ctx.player
  p.rope = nil
  if p.key and not p.key.used then
    Particles.poof(ctx.ents, p.x, p.y)
    p.key.taken = false
  end
  Player.reset(p, ctx.ents.spawn_points, ctx.cam, ctx.world)
  ctx.ents.arrows = {}
  ctx.ents.e_arrows = {}
end

-- Taking a hit: half a heart lost (unless still invulnerable from the
-- last hit); dying when the last half-heart is gone. Returns true when
-- the hit was fatal.
function Player.hurt(ctx)
  local p = ctx.player
  if p.invuln > 0 then return false end  -- shielded by i-frames
  p.hp = p.hp - config.player.half_hearts_per_hit
  if p.hp <= 0 then
    Player.die(ctx)
    return true
  end
  p.invuln = config.player.invuln_steps
  return false
end

-- One 30hz tick of the rope: attach to a newly anchored rope arrow,
-- detach on jump / lost anchor / removal, and winch the rope in or out.
-- Runs at the top of Player.physics, before movement.
function Player.rope_step(ctx)
  local p = ctx.player
  local rcfg = ctx.config.rope
  if p.rope_cd > 0 then p.rope_cd = p.rope_cd - 1 end

  if not p.rope then
    -- attach to the first anchored rope arrow not yet claimed
    if p.rope_cd == 0 then
      for _, a in ipairs(ctx.ents.arrows) do
        if a.active and a.stuck and a.kind == "rope" and not a.rope_taken then
          local px, py = p.x + p.w/2, p.y + p.h/2
          local dist = math.sqrt((px - a.x)^2 + (py - a.y)^2)
          p.rope = { arrow = a, length = math.max(rcfg.min_length, math.min(rcfg.max_length, dist)) }
          a.rope_taken = true
          break
        end
      end
    end
    if not p.rope then return end
  end

  local a = p.rope.arrow
  -- the anchor must still be embedded: the tip itself is retracted out of
  -- the wall face, so sample a few px deeper along the stuck direction
  -- (this also releases the rope when a door opens under the arrow)
  local embedded = a.on_slope and ctx.world:in_slope_solid(a.x, a.y)
  if not embedded then
    for d = 2, 6, 2 do
      if ctx.world:solid_for_arrow(a.x + (a.sdx or 0) * d, a.y + (a.sdy or 0) * d) then
        embedded = true
        break
      end
    end
  end
  if not a.active or not a.stuck or not embedded then
    p.rope = nil
    return
  end

  -- jump releases the rope; the current velocity carries the player on.
  -- Consumed here so the jump buffer never fires a normal jump, and with
  -- a short cooldown so the same arrow (or a second stuck one) cannot
  -- instantly re-grab the player.
  if ctx.input:pressed("jump") then
    p.rope = nil
    p.rope_cd = ctx.config.player.jump_buffer_frames
    return
  end

  -- winch: up shortens, down lengthens, within the length clamps
  if ctx.input:down("up") then
    p.rope.length = math.max(rcfg.min_length, p.rope.length - rcfg.winch_speed)
  elseif ctx.input:down("down") then
    p.rope.length = math.min(rcfg.max_length, p.rope.length + rcfg.winch_speed)
  end
end

-- One 30hz tick of player physics (movement, jump, terrain collision,
-- arrow platforms, key pickup/lock delivery, run cycle, void fall).
function Player.physics(ctx)
  local p = ctx.player
  local world = ctx.world
  local cfg = config.player
  local tw = config.tile_size

  if p.invuln > 0 then p.invuln = p.invuln - 1 end

  Player.rope_step(ctx)

  if not ctx.input:down("aim") then
    local ax = 0
    if ctx.input:down("left") then ax = -1 end
    if ctx.input:down("right") then ax =  1 end
    if ax ~= 0 then
      p.facing = ax
      local a = p.gr and cfg.acceleration or (cfg.acceleration * cfg.air_acceleration_scale)
      p.vx = p.vx + ax * a
    else
      local d = p.gr and (cfg.deceleration * p.fr)
                     or (cfg.deceleration * cfg.air_deceleration_scale)
      if p.vx > 0 then p.vx = math.max(0, p.vx - d)
      elseif p.vx < 0 then p.vx = math.min(0, p.vx + d) end
    end
    -- while swinging, the pendulum constraint governs speed instead of
    -- the walk cap (the swing's tangential momentum must survive)
    if not p.rope then
      p.vx = math.max(-cfg.walk_speed, math.min(cfg.walk_speed, p.vx))
    end
  else
    local d = p.gr and (cfg.deceleration * p.fr)
                   or (cfg.deceleration * cfg.air_deceleration_scale)
    if p.vx > 0 then p.vx = math.max(0, p.vx - d)
    elseif p.vx < 0 then p.vx = math.min(0, p.vx + d) end
  end
  if p.jbuf > 0 and p.coy > 0 then
    p.vy = Util.move_toward(p.vy, cfg.jump_velocity, cfg.jump_accel_initial)
    p.coy, p.jbuf = 0, 0
    p.j_frames = cfg.jump_hold_frames
  end

  if p.j_frames > 0 then
    if ctx.input:down("jump") and p.vy < 0 then
      p.vy = Util.move_toward(p.vy, cfg.jump_velocity, cfg.jump_accel)
      p.j_frames = p.j_frames - 1
    else
      if p.vy < 0 then p.vy = p.vy / 2 end
      p.j_frames = 0
    end
  end

  p.vy = p.vy + config.physics.gravity
  p.vy = math.min(p.vy, config.physics.max_fall_speed)

  -- rope pendulum: when the rope is taut, remove the outward radial
  -- component of the velocity so the player swings tangentially (gravity
  -- keeps feeding the swing); left/right input acts as tangential pumping
  if p.rope then
    local a = p.rope.arrow
    local cx, cy = p.x + p.w/2, p.y + p.h/2
    local rx, ry = cx - a.x, cy - a.y
    local dist = math.sqrt(rx*rx + ry*ry)
    if dist > p.rope.length and dist > 0 then
      local nx, ny = rx / dist, ry / dist
      local radial = p.vx * nx + p.vy * ny
      if radial > 0 then
        p.vx = p.vx - radial * nx
        p.vy = p.vy - radial * ny
      end
    end
  end

  p.x = p.x + p.vx
  world:resolve_x(p)
  world:check_walls(p)

  p.gr = false
  p.fr = 1.0
  p.y = p.y + p.vy
  world:resolve_y(p)
  world:resolve_slopes(p)
  Arrows.check_platforms(ctx)

  -- rope position clamp: after collision, never let the player drift
  -- beyond the rope length; pull back onto the circle (velocity that
  -- pointed outward was already removed above, so this only corrects
  -- positional drift and collision snags)
  if p.rope then
    local a = p.rope.arrow
    local cx, cy = p.x + p.w/2, p.y + p.h/2
    local rx, ry = cx - a.x, cy - a.y
    local dist = math.sqrt(rx*rx + ry*ry)
    if dist > p.rope.length then
      if dist > 0 then
        local scale = p.rope.length / dist
        p.x = a.x + rx * scale - p.w/2
        p.y = a.y + ry * scale - p.h/2
      else
        p.x, p.y = a.x - p.w/2, a.y - p.h/2
      end
      -- keep the resolved position out of solid tiles
      world:resolve_x(p)
      world:resolve_y(p)
      world:resolve_slopes(p)
    end
  end

  if p.gr then
    p.coy = cfg.coyote_frames
    p.j_frames = 0
    p.aimed_down = false
    if not p.prev_gr then p.land_frames = cfg.landing_frames end
    if p.land_frames > 0 then p.land_frames = p.land_frames - 1 end
  else
    p.coy = math.max(0, p.coy - 1)
    p.land_frames = 0
  end
  p.prev_gr = p.gr

  -- key interactions: pick a key up from the world, or grab it off any
  -- key-carrying arrow the player touches (flying or stuck); then carry
  -- it to a lock personally
  if not p.key then
    for _, k in ipairs(ctx.ents.keys) do
      if not k.taken
      and p.x < k.x+tw and p.x+p.w > k.x
      and p.y < k.y+tw and p.y+p.h > k.y then
        k.taken = true
        p.key   = k
        break
      end
    end
    if not p.key then
      for _, a in ipairs(ctx.ents.arrows) do
        if a.active and a.key and not (a.grab_cd and a.grab_cd > 0)
        and a.x >= p.x-1 and a.x <= p.x+p.w+1
        and a.y >= p.y-1 and a.y <= p.y+p.h+1 then
          p.key = a.key
          a.key = nil
          break
        end
      end
    end
  end
  if p.key then
    for _, lock in ipairs(ctx.ents.locks) do
      if not lock.triggered
      and Interactables.key_fits_lock(p.key, lock)
      and p.x < lock.x+tw and p.x+p.w > lock.x
      and p.y < lock.y+tw and p.y+p.h > lock.y then
        Interactables.trigger_lock(ctx.ents, lock)
        p.key.used = true  -- consumed; not released on death
        p.key      = nil
        break
      end
    end
  end

  -- run cycle: advance at the 30hz sim rate (twang.p8 advanced it in _draw
  -- at 30fps); the port previously ticked it from love.draw at 60fps
  if p.gr and p.vx ~= 0 and not ctx.input:down("aim") then
    run_tick = run_tick + 1
    if run_tick >= cfg.run_cycle_steps then
      run_tick, run_frame = 0, (run_frame + 1) % cfg.run_cycle_frames
    end
  else
    run_frame, run_tick = 0, 0
  end

  -- fell off the bottom of the world -> respawn
  if p.y > world.px_h + config.world.void_margin then Player.die(ctx) end
end

-- One 30hz tick of bow aiming: entering aim mode, turning (analog stick
-- owns the angle; arrows nudge when idle), power levels, and firing on
-- release. Run before physics each step.
function Player.aim_step(ctx)
  local p = ctx.player
  local cfg = config.aiming
  if ctx.input:down("aim") then
    if not p.was_aiming then
      -- first frame of aim mode: aim along the stick if pushed, else
      -- face straight ahead
      local sx, sy = ctx.input:aim_stick()
      if sx then
        p.aim_angle = Util.turn_from_direction(sx, sy)
      else
        p.aim_angle = p.facing > 0 and 0 or 0.5
      end
      p.aim_power  = cfg.start_power
      p.was_aiming = true
      p.aimed_down = false
    end
    -- analog aiming: the stick owns the angle; dpad/arrow left/right
    -- only nudges when the stick is idle
    local sx, sy = ctx.input:aim_stick()
    if sx then
      p.aim_angle = Util.turn_from_direction(sx, sy)
    elseif ctx.input:down("left") then
      p.aim_angle = (p.aim_angle + cfg.turn_rate) % 1
    elseif ctx.input:down("right") then
      p.aim_angle = (p.aim_angle - cfg.turn_rate) % 1
    end
    -- power levels: keyboard up/down or the physical dpad (the "up"/"down"
    -- buttons deliberately exclude the analog stick)
    if ctx.input:pressed("up") then
      p.aim_power = math.min(cfg.max_power, p.aim_power + 1)
    end
    if ctx.input:pressed("down") then
      p.aim_power = math.max(cfg.min_power, p.aim_power - 1)
    end
  else
    if p.was_aiming then
      if Util.p8sin(p.aim_angle) > cfg.downward_sin_threshold then
        p.aimed_down = true
      end
      Arrows.fire(ctx, p.aim_angle, p.arrow_kind)
      p.was_aiming = false
    end
    -- jumping while attached releases the rope (handled in rope_step);
    -- only buffer a normal jump when free
    if ctx.input:pressed("jump") and not p.rope then
      p.jbuf = config.player.jump_buffer_frames
    end
  end
  -- swap arrow type (normal <-> rope) on the dedicated button
  if ctx.input:pressed("swap") then
    p.arrow_kind = p.arrow_kind == "rope" and "normal" or "rope"
  end
  if p.jbuf > 0 then p.jbuf = p.jbuf - 1 end
end

-- Exposes the run cycle state for rendering and tests.
function Player.run_state()
  return run_frame, run_tick
end

return Player
