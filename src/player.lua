-- The player: state, respawn, fixed-timestep physics (with coyote time
-- and jump buffering; world time scales with ctx.dt), bow aiming/firing,
-- and key carrying.

local config = require("src.config")
local Util   = require("src.util")

local Camera       = require("src.camera")
local Particles    = require("src.particles")
local Interactables = require("src.interactables")
local Arrows       = require("src.arrows")
local WinchLog     = require("src.winchlog")

local Player = {}

-- Run cycle state (advances in world time -- the 30hz-step currency --
-- so the animation keeps its pace at any sim rate; twang.p8 advanced it
-- in _draw at 30fps). Deliberately not reset on respawn, like the original.
local run_frame, run_tick = 0, 0
-- The wall-run's animation cycle (same scheme, while the wall-run lasts).
local wallrun_frame, wallrun_tick = 0, 0

--- Builds a fresh player at `spawn` ({x=, y=} or nil for the cart default).
function Player.new(spawn)
  local cfg = config.player
  local p = {
    x = spawn and spawn.x or 8,
    y = spawn and spawn.y or 164,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, coy = 0, jbuf = 0, fr = 1.0,
    j_frames = 0,
    wall_l = false, wall_r = false,
    aim_angle = 0, aim_power = config.aiming.start_power,
    aim_force = 1.0,  -- analog launch-force scale (1 = power level's full speed)
    was_aiming = false, aimed_down = false,
    prev_gr = false, land_frames = 0,
    key = nil,  -- carried key object (taken from the world or an arrow)
    hp = config.player.hearts * 2,   -- health in half-hearts (drawn top-left)
    invuln = 0,  -- post-hit invulnerability steps remaining
    arrow_kind = "normal",  -- currently selected arrow type
                            -- ("normal"/"rope"/"spirit"/"bomb")
    spirit_armed = true,    -- the spirit fling's charge: one shot between
                            -- landings on solid ground (see Spirit.fire)
    guns = 0,    -- explosive-gun shots carried (collected from dead lasers)
    slide = false,  -- wall-sliding this step (falling pinned to a wall)
    rope = nil,  -- attached rope: { arrow = <anchored rope arrow>, length = px }
    rope_cd = 0, -- steps before another rope can attach (post-detach grace)
    winch = nil, -- winch reel in progress: { ent = <winch entity> }
    winch_grace = nil, -- steps after a winch release with movement input ignored
    wallrun = nil, -- active wall-run: { dir=, r=, c_end=, y0=, t= } (nil = none)
  }
  return p
end

-- Respawns: re-places the player at a random spawn point (reusing the
-- table so references stay valid).
function Player.reset(p, spawn_points, cam, world)
  local sp = spawn_points[math.random(#spawn_points)]
  p.x = sp and sp.x or 8
  p.y = sp and sp.y or 164
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
  p.aim_force = 1.0
  p.was_aiming = false
  p.aimed_down = false
  p.prev_gr = false
  p.land_frames = 0
  p.key = nil
  p.hp = config.player.hearts * 2
  p.invuln = 0
  p.arrow_kind = "normal"
  p.spirit_armed = true
  p.rope = nil
  p.rope_cd = 0
  p.winch = nil
  p.winch_grace = nil
  p.wallrun = nil
  p.slide = false
  p.wall_slide_side = nil
  p.arrow_stand = nil
  p.guns = p.guns or 0  -- the guns carried survive a death (you keep the pickup)
  p.ride = nil  -- no mover carries the body across a respawn
  -- the render-interpolation shadow lands with the body (no cross-map
  -- ease on respawn)
  p._px, p._py = p.x, p.y
  -- the respawn point picks the active room (no wipe on respawn); the
  -- camera then snaps under that room's clamp
  world:sync_room(p.x, p.y)
  if cam then
    Camera.snap(cam, p, world)
  end
end

-- Death: a carried (unconsumed) key drops back into the world where the
-- player fell, then respawn; arrows in flight are cleared (so any rope
-- attachment goes with them). The respawn point is the last touched
-- checkpoint flag (ctx.checkpoint) or, without one, a random spawn
-- point (the legacy behaviour).
function Player.die(ctx)
  local p = ctx.player
  ctx.freeze = 0  -- a fatal hit's stop ends with the respawn
  p.rope = nil
  p.winch = nil
  p.winch_grace = nil
  p.wallrun = nil
  p.slide = false
  p.wall_slide_side = nil
  p.arrow_stand = nil
  if p.key and not p.key.used then
    Particles.poof(ctx.ents, p.x, p.y)
    p.key.taken = false
  end
  local cp = ctx.checkpoint
  if cp then
    Player.reset(p, { cp }, ctx.cam, ctx.world)
  else
    Player.reset(p, ctx.ents.spawn_points, ctx.cam, ctx.world)
  end
  ctx.ents.arrows = {}
  ctx.ents.e_arrows = {}
  ctx.ents.rockets = {}
  ctx.ents.bombs = {}
end

-- Taking a hit: half a heart lost by default (unless still invulnerable
-- from the last hit); dying when the last half-heart is gone. `amount`
-- overrides the default damage in half-hearts (the laser rifleman's beam
-- costs a full heart). The test menu's invincibility toggle blocks all
-- damage (void falls still kill: death is a respawn mechanism, not
-- damage). `ix`/`iy` is the impact direction (arrow travel, the laser
-- beam, or from the melee enemy toward the player): the blood sprays the
-- opposite way, at the player's centre, with the player's own motion
-- added so it doesn't lag a moving body.
-- Returns true when the hit was fatal.
function Player.hurt(ctx, ix, iy, amount)
  if ctx.settings.invincible then return false end
  local p = ctx.player
  if p.invuln > 0 then return false end  -- shielded by i-frames
  p.hp = p.hp - (amount or config.player.half_hearts_per_hit)
  -- hitstop: the whole world freezes for a few steps when a body is
  -- hit (src/game.lua reads ctx.freeze; a poison-free handicap of the
  -- frozen frame — pending input and animations keep their state)
  if ctx.freeze then ctx.freeze = config.player.freeze_steps end
  -- blood before the death flow: a fatal hit respawns the player and
  -- would otherwise move them before the spray can spawn
  Particles.blood(ctx.ents, p.x + p.w/2, p.y + p.h/2,
    ix or -p.facing, iy or 0, p.vx, p.vy)
  if p.hp <= 0 then
    Player.die(ctx)
    return true
  end
  p.invuln = config.player.invuln_steps
  return false
end

-- One sim tick of the rope: attach to a newly anchored rope arrow,
-- detach on jump / lost anchor / removal, and winch the rope in or out.
-- Runs at the top of Player.physics, before movement; the reel speed
-- scales with ctx.dt (winching slows down in slow motion).
function Player.rope_step(ctx)
  local p = ctx.player
  local rcfg = ctx.config.rope
  local dt = ctx.dt
  if p.rope_cd > 0 then p.rope_cd = math.max(0, p.rope_cd - dt) end

  -- a winch reel owns the player until it releases (see Player.physics):
  -- no rope attach, no jump detach, no manual winching
  if p.winch then return end

  -- the wall-run owns the body while it lasts: no rope attach or detach
  if p.wallrun then return end

  if not p.rope then
    -- attach to the first anchored rope arrow not yet claimed. The
    -- anchor must be in REACH: a rope arrow stuck farther than the
    -- rope's max length never attaches -- the pendulum would clamp the
    -- length and SPRING the player up toward the anchor (hard yank)
    if p.rope_cd == 0 then
      for _, a in ipairs(ctx.ents.arrows) do
        if a.active and a.stuck and a.kind == "rope" and not a.rope_taken then
          local px, py = p.x + p.w/2, p.y + p.h/2
          local dist = math.sqrt((px - a.x)^2 + (py - a.y)^2)
          if dist <= ctx.config.rope.max_length then
            p.rope = { arrow = a, length = math.max(rcfg.min_length,
              math.min(rcfg.max_length, dist)) }
            a.rope_taken = true
            p.arrow_stand = nil  -- the swing owns the body now
            break
          end
        end
      end
    end
    if not p.rope then return end
  end

  local a = p.rope.arrow
  -- the anchor must still be embedded: the tip itself is retracted out of
  -- the wall face, so sample a few px deeper along the stuck direction
  -- (this also releases the rope when a door opens under the arrow)
  local embedded = false
  for d = 4, 12, 2 do
    if ctx.world:solid_for_arrow(a.x + (a.sdx or 0) * d, a.y + (a.sdy or 0) * d) then
      embedded = true
      break
    end
  end
  if not a.active or not a.stuck or not embedded then
    p.rope = nil
    return
  end

  -- jump releases the rope; the current velocity carries the player on.
  -- Consumed here so the jump buffer never fires a normal jump, and with
  -- a short cooldown so the same arrow (or a second stuck one) cannot
  -- instantly re-grab the player. Fresh press only: holding the button
  -- must not detach (a repeat edge would cut the swing mid-hold).
  if ctx.input:pressed_fresh("jump") then
    p.rope = nil
    p.rope_cd = ctx.config.player.jump_buffer_frames
    return
  end

  -- winch: up shortens, down lengthens, within the length clamps
  local winch_dir = 0
  if ctx.input:down("up") then winch_dir = -1
  elseif ctx.input:down("down") then winch_dir = 1 end
  if winch_dir ~= 0 then
    p.rope.length = math.max(rcfg.min_length, math.min(rcfg.max_length,
      p.rope.length + winch_dir * rcfg.winch_speed * ctx.dt))
  end
end

-- The wall-run trigger: when the player's centre sits inside one of the
-- line's first two tiles from a pushed end (the outermost tile, or one in
-- from it) while holding jump and pushing toward the line, the run
-- engages: the body is pinned into the band and carried along it at a
-- constant speed (see Player.wallrun_step). Blocked while roped or
-- winch-owned: those modes own the body.
function Player.wallrun_check(ctx)
  local p = ctx.player
  if p.rope or p.winch or p.arrow_stand
  or (p.winch_grace and p.winch_grace > 0) then return end
  local world = ctx.world
  local tw = config.tile_size
  local art = config.art_size
  local cx = math.floor((p.x + p.w/2) / tw)
  -- the wall-run band is the 16px art row containing the body's centre
  -- (two 8px rows of runnable cells)
  local rb = math.floor((p.y + p.h/2) / art)
  local c0, c1 = world:runnable_band_line(cx, rb * 2)
  if not c0 then return end
  local dir
  -- the centre must sit within the band's first two ART tiles from the
  -- pushed end (four 8px columns: indices 0..3), and the band must
  -- extend in the pushed direction. Right wins when both are held, like
  -- the walk motor's ax.
  if ctx.input:down("right") and cx < c1 and cx - c0 <= 3 then
    dir = 1
  elseif ctx.input:down("left") and cx > c0 and c1 - cx <= 3 then
    dir = -1
  end
  if not dir or not ctx.input:down("jump") then return end
  p.wallrun = { dir = dir, r = rb, c_end = dir > 0 and c1 or c0,
                y0 = p.y, t = 0 }
  p.vx = dir * config.wallrun.speed
  p.vy = 0
  p.facing = dir
  -- a leftover jump (buffer or hold) must not fire during or after the run
  p.jbuf, p.j_frames, p.coy = 0, 0, 0
end

-- One sim tick of the wall-run: carries the player through the band at a
-- constant speed while the run direction is held, and hands off at the
-- line's far end (a jump when jump is still held; momentum plus a fall
-- when not). Replaces the normal movement pass entirely: no gravity, no
-- collision (the band's tiles are pass-through), no jump buffering.
function Player.wallrun_step(ctx)
  local p = ctx.player
  local wr = p.wallrun
  local cfg = config.wallrun
  local world = ctx.world
  local dt = ctx.dt
  local tw = config.tile_size
  local dir = wr.dir

  p.gr, p.fr = false, 1.0

  -- a winch capture owns the body from here on: hand control over (the
  -- reel takes over on the next step's normal pass)
  if p.winch then
    p.wallrun = nil
    return
  end

  -- the ride y eases onto the band's centre line over settle_steps (the
  -- smooth transition); no gravity while pinned. The band is a 16px art
  -- row (config.art_size).
  wr.t = wr.t + dt
  local art = config.art_size
  local pin_y = wr.r * art + (art - p.h) / 2
  p.y = wr.y0 + (pin_y - wr.y0) * math.min(1, wr.t / cfg.settle_steps)
  p.vy = 0

  -- releasing the run direction: stop and drop straight down
  if not ctx.input:down(dir > 0 and "right" or "left") then
    p.wallrun = nil
    p.vx, p.vy = 0, 0
    return
  end

  -- solid terrain at the leading edge's next step (a closed door placed
  -- mid-band) ends the run the same way
  local lead_x
  if dir > 0 then lead_x = p.x + p.w + p.vx * dt
  else lead_x = p.x + p.vx * dt end
  if world:solid_at(lead_x, pin_y + p.h/2) then
    p.wallrun = nil
    p.vx, p.vy = 0, 0
    return
  end

  p.x = p.x + p.vx * dt

  -- the wall-run's own animation cycle (advances in world time, like the
  -- ground run cycle)
  wallrun_tick = wallrun_tick + dt
  if wallrun_tick >= cfg.cycle_steps then
    wallrun_tick = wallrun_tick - cfg.cycle_steps
    wallrun_frame = (wallrun_frame + 1) % cfg.cycle_frames
  end

  -- reaching the line's far end: a jump while jump is held, otherwise the
  -- forward momentum carries and gravity resumes
  local reached
  if dir > 0 then
    reached = p.x + p.w >= wr.c_end * tw
  else
    reached = p.x <= (wr.c_end + 1) * tw
  end
  if reached then
    p.wallrun = nil
    if ctx.input:down("jump") then
      p.vy = config.player.jump_velocity
      p.j_frames = config.player.jump_hold_frames
    end
  end
end

-- One sim tick of player physics (movement, jump, terrain collision,
-- arrow platforms, key pickup/lock delivery, run cycle, void fall).
-- Advances world time by ctx.dt steps: positions, velocities and the
-- step-counted timers all scale with it (dt is 1 normally, 1 /
-- aiming.slow_motion_steps while aiming).
function Player.physics(ctx)
  local p = ctx.player
  local ents = ctx.ents
  local world = ctx.world
  local cfg = config.player
  local art = config.art_size
  local dt = ctx.dt

  if p.invuln > 0 then p.invuln = math.max(0, p.invuln - dt) end

  Player.rope_step(ctx)

  -- winch ownership: during a reel and for `config.winch.stick_grace`
  -- steps after release, movement input is ignored entirely (no
  -- acceleration, no damping, no walk cap) so the pull/throw physics
  -- can play out untouched. The aim button still works (deliberate).
  if p.winch_grace and p.winch_grace > 0 then
    p.winch_grace = math.max(0, p.winch_grace - dt)
    if WinchLog.on() then
      WinchLog.log("grace", {
        step = ctx.menu and ctx.menu.step_count or 0,
        remaining = p.winch_grace,
        vx = p.vx, vy = p.vy, gr = p.gr,
      })
    end
  end
  -- the wall-run owns the movement pass while it lasts (no walk motor,
  -- no gravity, no collision: the band's tiles are pass-through);
  -- otherwise the trigger may engage it here, before any movement runs
  if not p.wallrun then Player.wallrun_check(ctx) end
  if p.wallrun then
    Player.wallrun_step(ctx)
  else
    local motor = p.winch or (p.winch_grace ~= nil and p.winch_grace > 0)
    -- an arrow perch owns movement: nothing to walk on, exits only via
    -- jump or a shove (Arrows.check_platforms maintains the perch)
    if p.arrow_stand then motor = true end
    if motor then
      if p.arrow_stand then
        -- perch: no walk motor, no air damping; the fall is stopped
        -- dead (feet pinned by check_platforms below; vx bleeds to zero
        -- so a caught body doesn't drift off its arrow)
        p.vx = 0
      elseif not (p.winch or (p.winch_grace ~= nil and p.winch_grace > 0)) then
        -- (velocity comes from a winch reel below, or the throw itself)
      end
    elseif not ctx.input:down("aim") then
      local ax = 0
      if ctx.input:down("left") then ax = -1 end
      if ctx.input:down("right") then ax =  1 end
      -- the fire's deaf window also covers HELD movement: an arrow
      -- released while a direction is held must not lurch the body to
      -- a stop-and-go (the stick ignore lands mid-update, so both
      -- stick-driven and keyboard movement fall under its frame count)
      local Iface = ctx.input  -- stick_deaf / held reads below
      if Iface.stick_deaf and Iface.stick_deaf > 0 then ax = 0 end
      -- the airborne rope pendulum coasts: gravity and the radial
      -- constraint govern the swing, so the walk motor's air damping
      -- stands down (the swing's momentum must survive)
      local coasting = p.rope ~= nil and not p.gr
      -- a slide presses the body against the wall: no outward drive
      if p.slide then
        local away = (p.wall_slide_side or 0) > 0 and -1 or 1
        if ax == away then ax = 0 end  -- (release handled below the fall cap)
      end
      if ax ~= 0 then
        p.facing = ax
        local a = p.gr and cfg.acceleration or (cfg.acceleration * cfg.air_acceleration_scale)
        p.vx = p.vx + ax * a * dt
      else
        local d = coasting and 0
                       or (p.gr and (cfg.deceleration * p.fr)
                                or (cfg.deceleration * cfg.air_deceleration_scale))
        if p.vx > 0 then p.vx = math.max(0, p.vx - d * dt)
        elseif p.vx < 0 then p.vx = math.min(0, p.vx + d * dt) end
      end
      -- while swinging, the pendulum constraint governs speed instead of
      -- the walk cap (the swing's tangential momentum must survive)
      if not p.rope then
        p.vx = math.max(-cfg.walk_speed, math.min(cfg.walk_speed, p.vx))
      end
    else
      local d = p.gr and (cfg.deceleration * p.fr)
                     or (cfg.deceleration * cfg.air_deceleration_scale)
      if p.vx > 0 then p.vx = math.max(0, p.vx - d * dt)
      elseif p.vx < 0 then p.vx = math.min(0, p.vx + d * dt) end
    end
    if p.jbuf > 0 and p.coy > 0 then
      p.vy = Util.move_toward(p.vy, cfg.jump_velocity, cfg.jump_accel_initial * dt)
      p.coy, p.jbuf = 0, 0
      p.j_frames = cfg.jump_hold_frames
      -- takeoff dust + a small camera thud (juice: jumping reads)
      Particles.dust(ents, p.x + p.w/2, p.y + p.h, 0.25)
      Camera.thud(ctx.cam, config.camera.thud_jump)
    end

    -- THE WALL LEAP: the perch's jump, always launched AWAY from the
    -- wall. It rides the same buffered press as the ground jump (set
    -- above when coyote lingered from the catch) and fires on the same
    -- line, same phase, same hold window, same dust: hugging an arrow
    -- and jumping is the ground jump's twin, not a late special-case
    -- launch. A wallslide-jump with no perch no longer leaps.
    if p.arrow_stand and p.jbuf > 0 then
      local side = p.arrow_stand.side
      p.jbuf = 0
      p.coy = 0
      p.j_frames = cfg.jump_hold_frames
      p.vy = Util.move_toward(p.vy, cfg.jump_velocity, cfg.jump_accel_initial * dt)
      p.vx = -(side or p.facing or 1) * cfg.walljump_push
      p.facing = -(side or p.facing or 1)
      p.arrow_stand = nil
      Camera.thud(ctx.cam, config.camera.thud_jump)
      Particles.dust(ctx.ents, p.x + p.w/2, p.y + p.h, 0.4)
    end

    -- an arrow perch pins the fall: vy is zeroed every step (gravity
    -- pulls, the perch holds) — the body sits still until it jumps or
    -- the arrow is destroyed
    if p.arrow_stand then
      p.vy = 0
    end

    if p.j_frames > 0 then
      if ctx.input:down("jump") and p.vy < 0 then
        p.vy = Util.move_toward(p.vy, cfg.jump_velocity, cfg.jump_accel * dt)
        p.j_frames = math.max(0, p.j_frames - dt)
      else
        if p.vy < 0 then p.vy = p.vy / 2 end
        p.j_frames = 0
      end
    end

    -- heavier gravity on descent (vy > 0): the tail end of each jump
    -- drops fast, which reads as a snappier arc
    local g = config.physics.gravity
    if p.vy > 0 then g = g * config.physics.fall_gravity_scale end
    p.vy = p.vy + g * dt
    p.vy = math.min(p.vy, config.physics.max_fall_speed)

    -- wall slide (Celeste-style, no grab): while airborne and falling
    -- against a wall the body presses itself to the wall and descends
    -- at the slide speed; pushing AWAY from the wall releases. Objects
    -- own walls via solid_at (doors/movers/pushers included); the
    -- slide is inert while roped or winch-owned (the swing owns the body).
    p.slide = false
    p.wall_slide_side = nil
    if not p.gr and not p.rope and not p.winch and not p.wallrun
    and p.vy > 0 and not p.arrow_stand then
      world:check_walls(p)
      local side = p.wall_r and 1 or (p.wall_l and -1 or nil)
      if side then
        local pushing_away = (side > 0 and ctx.input:down("left"))
                          or (side < 0 and ctx.input:down("right"))
        if not pushing_away then
          p.slide = true
          p.wall_slide_side = side
          p.vy = math.min(p.vy, cfg.slide_speed)
        end
      end
    end


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

    -- winch reel: override the velocity with a pull straight toward the
    -- winch centre (after gravity and the walk logic, so nothing fights
    -- the motor; the pull accelerates like a spooling-up high-torque
    -- motor). The rope pendulum above is inert - p.rope is nil here.
    -- The throw direction carried from the entry side is refreshed each
    -- step the pull is active (still outside the pass radius), so the
    -- release can never invert it if the last step overshoots the centre.
    if p.winch then
      local w = p.winch.ent
      local wcx, wcy = w.x + art/2, w.y + art/2
      local px, py = p.x + p.w/2, p.y + p.h/2
      local rx, ry = wcx - px, wcy - py
      local dist = math.sqrt(rx*rx + ry*ry)
      p.winch.speed = math.min(config.winch.max_reel_speed,
        (p.winch.speed or 0) + config.winch.reel_accel * dt)
      if dist > config.winch.pass_radius and dist > 0 then
        local nx, ny = rx / dist, ry / dist
        p.vx = nx * p.winch.speed
        p.vy = ny * p.winch.speed
        p.winch.dir_x, p.winch.dir_y = nx, ny
      end
      if WinchLog.on() then
        WinchLog.log("reel", {
          step = ctx.menu and ctx.menu.step_count or 0,
          dist = dist, speed = p.winch.speed,
          dir_x = p.winch.dir_x or 0, dir_y = p.winch.dir_y or 0,
          vx = p.vx, vy = p.vy,
        })
      end
    end

    p.x = p.x + p.vx * dt
    world:resolve_x(p)
    world:check_walls(p)

    p.gr = false
    p.fr = 1.0
    p.y = p.y + p.vy * dt
    world:resolve_y(p)
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
      end
    end

    -- winch release: once the player's centre is inside the pass radius
    -- the motor cuts the line; the built-up reel momentum (topped up to a
    -- guaranteed minimum) throws them through the centre and out the
    -- opposite side from the one they hit it from. The direction is the
    -- one carried from the entry side (refreshed every reel step while
    -- outside the pass radius), never recomputed from the current radial -
    -- overshooting the centre must not invert the throw.
    if p.winch then
      local w = p.winch.ent
      local wcx, wcy = w.x + art/2, w.y + art/2
      local px, py = p.x + p.w/2, p.y + p.h/2
      local rx, ry = wcx - px, wcy - py
      local dist = math.sqrt(rx*rx + ry*ry)
      if dist <= config.winch.pass_radius then
        local spd = math.max(p.winch.speed or 0, config.winch.min_throw_speed)
        local dx, dy = p.winch.dir_x or 0, p.winch.dir_y or 0
        if dx == 0 and dy == 0 and dist > 0 then
          -- no stored direction (should not happen): radial as fallback
          dx, dy = rx / dist, ry / dist
        end
        p.vx = dx * spd
        p.vy = dy * spd
        p.winch = nil
        p.gr = false
        -- the throw plays out untouched for stick_grace steps; the same
        -- window also keeps a leftover stuck rope arrow from snapping the
        -- pendulum back on and eating the momentum
        p.winch_grace = config.winch.stick_grace
        p.rope_cd = config.winch.stick_grace
        if WinchLog.on() then
          WinchLog.log("release", {
            step = ctx.menu and ctx.menu.step_count or 0,
            dist = dist, spd = spd,
            throw_dx = dx, throw_dy = dy,
            vx = p.vx, vy = p.vy,
            -- dot of the throw against the player->winch vector: negative
            -- would mean the throw points back the way they came
            dot = dx * rx + dy * ry,
          })
        end
        Particles.poof(ctx.ents, wcx, wcy)
      end
    end
  end

  if p.gr then
    p.coy = cfg.coyote_frames
    p.j_frames = 0
    p.aimed_down = false
    if not p.prev_gr then
      p.land_frames = cfg.landing_frames
      -- hard landings kick up dust (and a camera thud: see Camera.thud)
      local fall = p.vy
      Particles.dust(ents, p.x + p.w/2, p.y + p.h,
        math.min(1, fall / config.physics.max_fall_speed))
      local strength = config.camera.thud_land
        * math.min(1, fall / config.physics.max_fall_speed)
      if strength > 0.2 then Camera.thud(ctx.cam, strength) end
      -- landing on a spring pad fires it: the vault replaces the landing
      for _, spring in ipairs(ents.springs) do
        if Interactables.spring_vault(ents, spring, p) then
          if not spring.ext then
            spring.ext = config.springs.extension_frames
          end
          break
        end
      end
      p.vy = math.min(p.vy, 0)
    end
    if p.land_frames > 0 then p.land_frames = math.max(0, p.land_frames - dt) end
    -- standing on solid ground refills the spirit fling's charge: one
    -- shot between landings (see Spirit.fire)
    p.spirit_armed = true
  else
    p.coy = math.max(0, p.coy - dt)
    p.land_frames = 0
  end
  p.prev_gr = p.gr

  -- the stick grace ends as soon as the throw has landed: the arc's
  -- physics have played out, so control returns the same step (no
  -- frictionless coasting with the stick ignored)
  if p.winch_grace and p.gr then p.winch_grace = nil end

  -- key interactions: pick a key up from the world, or grab it off any
  -- key-carrying arrow the player touches (flying or stuck); then carry
  -- it to a lock personally. Proximity boxes are padded so brushing past
  -- a key or lock still counts.
  if not p.key then
    local kpad = config.keys.pickup_pad
    for _, k in ipairs(ctx.ents.keys) do
      if not k.taken
      and p.x < k.x+art+kpad and p.x+p.w > k.x-kpad
      and p.y < k.y+art+kpad and p.y+p.h > k.y-kpad then
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
    local lpad = config.keys.lock_pad
    for _, lock in ipairs(ctx.ents.locks) do
      if not lock.triggered
      and Interactables.key_fits_lock(p.key, lock)
      and p.x < lock.x+art+lpad and p.x+p.w > lock.x-lpad
      and p.y < lock.y+art+lpad and p.y+p.h > lock.y-lpad then
        Interactables.trigger_lock(ctx.ents, lock)
        p.key.used = true  -- consumed; not released on death
        p.key      = nil
        break
      end
    end
  end

  -- checkpoint flags: touching one makes it the respawn point (a small
  -- poof marks the handover; re-touching the current one is silent)
  if #ctx.ents.checkpoints > 0 then
    local cpad = config.checkpoints.touch_pad
    for _, cp in ipairs(ctx.ents.checkpoints) do
      if p.x < cp.x+art+cpad and p.x+p.w > cp.x-cpad
      and p.y < cp.y+art+cpad and p.y+p.h > cp.y-cpad
      and ctx.checkpoint ~= cp then
        ctx.checkpoint = cp
        Particles.poof(ctx.ents, cp.x + art/2, cp.y + art/2)
        break
      end
    end
  end

  -- dropped guns: walking into one collects it as one explosive shot
  -- (the bow's next normal firing launches the gun itself)
  for _, g in ipairs(ctx.ents.guns) do
    if not g.taken
    and p.x < g.x+art+config.gun.pickup_pad
    and p.x+p.w > g.x-config.gun.pickup_pad
    and p.y < g.y+art+config.gun.pickup_pad
    and p.y+p.h > g.y-config.gun.pickup_pad then
      g.taken = true
      p.guns = (p.guns or 0) + 1
      Particles.poof(ctx.ents, g.x + art/2, g.y + art/2)
      break
    end
  end

  -- run cycle: advances in world time (scales with the step's dt, so
  -- slow motion slows the animation with the body). While wall-running
  -- the ground cycle holds reset and the wall-run advances its own.
  if p.wallrun then
    run_frame, run_tick = 0, 0
  elseif p.gr and p.vx ~= 0 and not ctx.input:down("aim") then
    run_tick = run_tick + dt
    if run_tick >= cfg.run_cycle_steps then
      run_tick = run_tick - cfg.run_cycle_steps
      run_frame = (run_frame + 1) % cfg.run_cycle_frames
    end
  else
    run_frame, run_tick = 0, 0
    wallrun_frame, wallrun_tick = 0, 0
  end

  -- fell off the bottom of the world -> respawn
  if p.y > world.px_h + config.world.void_margin then Player.die(ctx) end
end

-- Arrow selection: cycles the equipped arrow type (normal -> rope ->
-- spirit -> bomb -> normal) on the dedicated button. Runs every step,
-- entirely outside of aim mode, so the player can cycle arrow types
-- whenever they like. With the test menu's "special arrows hidden"
-- toggle on (the default), the bomb and spirit drop out of the cycle:
-- normal -> rope -> normal; an equipped special is unequipped at once
-- (nothing unreachable stays in the bow's hands).
local function next_arrow_kind(kind, no_special)
  if no_special then return kind == "rope" and "normal" or "rope" end
  return kind == "normal" and "rope"
       or kind == "rope" and "spirit"
       or kind == "spirit" and "bomb" or "normal"
end
function Player.arrow_step(ctx)
  local p = ctx.player
  local no_special = not ctx.settings or ctx.settings.no_special
  if no_special and p.arrow_kind ~= "normal" and p.arrow_kind ~= "rope" then
    p.arrow_kind = "normal"  -- a hidden special is unequipped at once
  end
  -- fresh press only: one press cycles one kind -- the btnp-style
  -- repeat of a held button must not spin the quiver around
  if ctx.input:pressed_fresh("swap") then
    p.arrow_kind = next_arrow_kind(p.arrow_kind, no_special)
  end
end

-- One sim tick of bow aiming: entering aim mode, turning (analog stick
-- owns the angle; arrows nudge when idle), power levels, and firing on
-- release. Run before physics each step. Aiming itself runs in real
-- time (the bow stays fully responsive while the world is slowed).
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
      p.aim_force  = 1.0
      p.was_aiming = true
      p.aimed_down = false
    end
    -- analog aiming: the stick owns the angle; dpad/arrow left/right
    -- only nudges when the stick is idle
    local sx, sy = ctx.input:aim_stick()
    if sx then
      p.aim_angle = Util.turn_from_direction(sx, sy)
      -- analog force: how far the stick sits from zero (remapped from
      -- the deadzone edge to full tilt) scales the launch speed, so a
      -- light tilt lobs gently and full tilt fires at the power level's
      -- full speed; the last drawn force persists if the stick returns
      -- to idle, like the angle does
      local mag = math.sqrt(sx * sx + sy * sy)
      local t = Util.clamp(
        (mag - cfg.force_deadzone) / (1 - cfg.force_deadzone), 0, 1)
      p.aim_force = cfg.min_force_scale + (1 - cfg.min_force_scale) * t
    elseif ctx.input:down("left") then
      p.aim_angle = (p.aim_angle + cfg.turn_rate) % 1
    elseif ctx.input:down("right") then
      p.aim_angle = (p.aim_angle - cfg.turn_rate) % 1
    end
    -- the PERCH's aim clamp: standing on an arrow stuck in a wall, the
    -- aim is limited to the 180 degrees pointing AWAY from that wall --
    -- you cannot fire back into the wall you lean against. Wall on the
    -- body's right (side = 1): aim turn restricted to 0.25..0.75 (down
    -- through left to up); wall on the left: 0.75..1.25, i.e. up
    -- through right to down. The stick, the keyboard nudge and the
    -- entering angle all pass through the clamp.
    if p.arrow_stand then
      p.aim_angle = Util.clamp_aim_away(p.aim_angle, p.arrow_stand.side)
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
      Arrows.fire(ctx, p.aim_angle, p.arrow_kind, p.aim_force)
      -- the released shot deafens the analog stick AND held movement
      -- for cfg.stick_ignore_frames (the walk motor reads the window):
      -- the bow hand's aim deflection / a held direction must not
      -- lurch the body the step the bow lets go. The spirit's
      -- recoil-launch rides its own grace window instead.
      if p.arrow_kind ~= "spirit" then
        ctx.input:ignore_stick(cfg.stick_ignore_frames)
        -- juice: the shot's report -- a small puff along the aim plus a
        -- tiny camera thud (the gun's is chunkier, see Arrows.fire)
        local is_gun = false
        for _, a in ipairs(ctx.ents.arrows) do
          if a.kind == "gun" then is_gun = true break end
        end
        Particles.fire_puff(ctx.ents, p.x + p.w/2, p.y + p.h/2,
          Util.p8cos(p.aim_angle), Util.p8sin(p.aim_angle))
        Camera.thud(ctx.cam, is_gun and config.camera.thud_gun
          or config.camera.thud_fire)
      end
      p.was_aiming = false
    end
    -- jumping while attached releases the rope (handled in rope_step);
    -- only buffer a normal jump when free. A winch reel is unstoppable,
    -- so no jump buffer there either; a wall-run owns the jump state
    -- too. Fresh press only: one press, one jump -- a held button never
    -- refills the buffer (no auto-bunny-hop on landing). A perch counts
    -- as free: its buffered press IS the wall leap (Player.physics).
    if ctx.input:pressed_fresh("jump") and not p.rope and not p.winch
    and not p.wallrun then
      p.jbuf = config.player.jump_buffer_frames
    end
  end
  if p.jbuf > 0 then
    p.jbuf = math.max(0, p.jbuf - (ctx.dt or 30 / config.sim.rate))
  end
end

-- Exposes the run cycle state for rendering and tests.
function Player.run_state()
  return run_frame, run_tick
end

-- Exposes the wall-run cycle state for rendering and tests.
function Player.wallrun_state()
  return wallrun_frame, wallrun_tick
end

return Player
