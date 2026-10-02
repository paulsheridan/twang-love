-- Arrows: the player's arrows (flight, bounce, stick, key carrying,
-- switch/lock/enemy hits) and the enemies' arrows.
--
-- Player arrows act as one-tile-wide platforms ONLY when embedded in a
-- vertical wall (see check_platforms), can carry keys to locks, and
-- bounce off bounce-flagged surfaces a limited number of times before
-- spinning out. The bow's third arrow kind, the spirit, is not an arrow at all:
-- fire() hands it to src/spirit.lua, a ghostly recoil-launch that
-- flings the player along the OPPOSITE of the aim direction (a burst
-- of particles marks the force) instead of sticking or killing. The
-- fourth kind, the bomb arrow, flies like a normal arrow but detonates
-- on any contact (Arrows.detonate_bomb): a direct enemy hit kills the
-- touched enemy, then the blast shoves the player, nearby enemies and
-- enemy projectiles radially away from the blast centre with proximity
-- falloff -- the bow's movement bomb. The shared zone-driven shove
-- (Arrows.shove) also powers the pusher device's two variants: the
-- updraft's straight-up column and the outdraft's up-and-away cone.
-- None of the bow's own work moves the camera: the frame never shakes
-- (see src/camera.lua).

local config = require("src.config")
local Util   = require("src.util")
local Particles    = require("src.particles")
local Movers       = require("src.movers")
local Interactables = require("src.interactables")
local WinchLog = require("src.winchlog")
local Rockets = require("src.rockets")
local Bombs = require("src.bombs")
local Spirit = require("src.spirit")

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
      if world:solid_for_arrow(nx, ny) then
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

-- Arrow noise: enemies read the player's arrows as movement. A stuck
-- arrow alerts every enemy within `enemies.arrow_alert_radius` of its
-- landing point DEFENSELESSLY (no line of sight needed: they heard the
-- thunk) — the brain's investigate takes over from the spot. Flying
-- arrows are picked up by the brains themselves (Enemies.update reads
-- in-flight player arrows through sight). Player arrows only: enemy
-- darts are the enemies' own gunfire.
local function notify_arrow_contact(ctx, a, x, y)
  if a.kind == "rope" then return end  -- a silent tool, not a fuss
  local radius = config.enemies.arrow_alert_radius
  local r2 = radius * radius
  for _, e in ipairs(ctx.ents.enemies) do
    local ex, ey = e.x + e.w/2, e.y + e.h/2
    local dx, dy = x - ex, y - ey
    if dx*dx + dy*dy <= r2 then
      e.last_known = { x = x, y = y }
      if e.state == "patrol" then
        e.state = "investigate"
        e.investigate_t = config.enemies.investigate_timeout
      end
    end
  end
end

-- Where a shot leaves a body: the point on box `b`'s boundary reached by
-- walking from (x, y) along the shot's unit heading (dx, dy) — the far
-- face of the wall of meat the arrow pierced, for the exit blood spray
-- (Particles.blood_exit). An axis the shot is not travelling down never
-- bounds the walk; a degenerate shot starting on the boundary exits
-- where it entered.
local function exit_point(b, x, y, dx, dy)
  local tx, ty = math.huge, math.huge
  if dx > 0 then tx = (b.x + b.w - x) / dx
  elseif dx < 0 then tx = (b.x - x) / dx end
  if dy > 0 then ty = (b.y + b.h - y) / dy
  elseif dy < 0 then ty = (b.y - y) / dy end
  local t = math.min(tx, ty)
  return x + dx * t, y + dy * t
end

-- The shared shove: everything whose position a `zone(bx, by)` sample
-- accepts is knocked along the unit vector the zone returns --
--
--   * the player, harmlessly (never damaged, no i-frames spent): the
--     knock is ADDED to their velocity -- it stacks with jump and swing
--     momentum, the point of the tool -- and rides the `grace` window so
--     the walk cap cannot clamp it (a horizontal blast would otherwise
--     be clamped to walk speed the step after the boom); a launch caught
--     mid-wall-run hands the body over so the shove plays out through
--     the grace too
--   * enemies, shoved along the flow and never killed by the shove
--     itself
--   * enemy projectiles: rockets knocked off their heading (the homing
--     re-curves them later), thrown bombs and darts knocked off course
--
-- A zone maps a target's centre to (kx, ky, strength) -- the unit knock
-- direction and the shove impulse -- or nil when the target lies outside
-- it (the bomb's radial proximity falloff; the outdraft's up-and-away
-- sector; the updraft's fixed straight-up column).
function Arrows.shove(ctx, zone, grace)
  local ents = ctx.ents

  for _, e in ipairs(ents.enemies) do
    local kx, ky, s = zone(e.x + e.w/2, e.y + e.h/2)
    if kx then
      e.vx, e.vy = e.vx + kx * s, e.vy + ky * s
      if e.vy < 0 then e.gr = false end
    end
  end

  local p = ctx.player
  local kx, ky, s = zone(p.x + p.w/2, p.y + p.h/2)
  if kx then
    -- the shove ADDS to the body's motion, so a running start carries
    -- through the launch (and the grace keeps the walk cap off it)
    p.vx, p.vy = p.vx + kx * s, p.vy + ky * s
    if p.vy < 0 then
      p.gr = false
      p.j_frames = 0
      p.wallrun = nil
    end
    -- the perch can't withstand a shove either: whatever the knock
    -- vector, an arrow-stand ends (the fall stops differently now)
    p.arrow_stand = nil
    -- the knock knocks the rope line off and the reel loose; the knock
    -- itself plays out untouched (movement input ignored, no walk cap)
    -- until it lapses or the player lands
    p.rope = nil
    p.winch_grace = grace
    p.rope_cd = grace
  end

  for _, r in ipairs(ents.rockets) do
    if r.active then
      local kx, ky, s = zone(r.x, r.y)
      if kx then r.kx, r.ky = kx * s, ky * s end
    end
  end
  for _, b in ipairs(ents.bombs) do
    if b.active then
      local kx, ky, s = zone(b.x, b.y)
      if kx then
        b.vx, b.vy = b.vx + kx * s, b.vy + ky * s
      end
    end
  end
  for _, a in ipairs(ents.e_arrows) do
    if a.active and not a.hit_stick then
      local kx, ky, s = zone(a.x, a.y)
      if kx then
        a.vx, a.vy = a.vx + kx * s, a.vy + ky * s
      end
    end
  end
end

-- The bomb arrow's detonation: a flash ring and spark burst, then the
-- shared shove with a linear proximity falloff from `push` at the
-- blast's centre down to its `min_push_scale` share at the rim (see
-- Arrows.shove for the per-target effects).
--
-- A blast at a target's exact centre shoves straight up.
function Arrows.detonate_bomb(ctx, x, y)
  local ents = ctx.ents
  local cfg = ctx.config.bomb_arrow
  table.insert(ents.booms, { x = x, y = y,
    t = ctx.config.enemies.boom_frames, r = cfg.blast_radius })
  Particles.boom(ents, x, y)
  Particles.poof(ents, x, y)
  -- the burnt remains: the bomb arrow always detonates against a
  -- surface, so the struck face keeps sparking and smoking for a beat
  Particles.aftermath(ents, ctx.world, x, y, true)
  Arrows.shove(ctx, function(bx, by)
    local dx, dy = bx - x, by - y
    local d = math.sqrt(dx*dx + dy*dy)
    if d > cfg.blast_radius then return nil end
    if d == 0 then return 0, -1, cfg.push end
    return dx / d, dy / d,
      cfg.push * math.max(cfg.min_push_scale, 1 - d / cfg.blast_radius)
  end, cfg.shove_grace)
end

-- The pusher's strike (a player arrow's tip entered the device's tile;
-- the arrow is consumed by the strike site): the shared flash ring --
-- sized to the variant's catch radius -- and a spark burst, then the
-- variant's shove at CONSTANT strength everywhere in its catch zone: a
-- predictable launcher. The ring draws, but the camera never shakes.
--
--   updraft: everything inside the box over the device's column plus
--   `side` tiles to either side, from the device's top edge up to
--   `reach` px above it, is launched straight up.
--   outdraft: everything within `radius` of the device's tile centre
--   whose radial lies inside the cone half-angle from straight up is
--   shoved along that radial, up-and-away.
function Arrows.trigger_pusher(ctx, pu)
  local ents = ctx.ents
  local cfg = ctx.config.pusher
  local tw = ctx.config.tile_size
  local variant = pu.variant
  local grace = pu.shove_grace or cfg.shove_grace
  local push = pu.push or cfg.push
  local cx, cy = pu.x + ctx.config.art_size/2, pu.y + ctx.config.art_size/2

  local zone, joy -- joy: the flash ring's radius
  if variant == "updraft" then
    local side  = (pu.side  or cfg.up.side)  * ctx.config.art_size
    local top   = pu.y - (pu.reach or cfg.up.reach)
    local left  = pu.x - side
    local right = pu.x + ctx.config.art_size + side
    joy = (pu.reach or cfg.up.reach)
    -- the catch box: the device's column plus the side band, from the
    -- device's top edge to `reach` px above it; the knock is straight
    -- up at full strength wherever the target sits in the box
    zone = function(bx, by)
      if bx < left or bx >= right
      or by < top or by > pu.y then return nil end
      return 0, -1, push
    end
  else
    local radius = pu.radius or cfg.out.radius
    local cone = math.rad(pu.cone or cfg.out.cone)
    local cos_cone = math.cos(cone)
    joy = radius
    -- the catch sector: within `radius` of the centre and ABOVE it,
    -- inside the cone around straight up (dot of the unit radial with
    -- the up vector beats the cone's cosine); the knock rides the
    -- radial, up-and-away
    zone = function(bx, by)
      local dx, dy = bx - cx, by - cy
      local d = math.sqrt(dx*dx + dy*dy)
      if d > radius or dy >= 0 then return nil end
      if -dy / d < cos_cone then return nil end
      return dx / d, dy / d, push
    end
  end

  table.insert(ents.booms, { x = cx, y = cy,
    t = ctx.config.enemies.boom_frames, r = joy })
  Particles.boom(ents, cx, cy)
  Particles.poof(ents, cx, cy)
  Arrows.shove(ctx, zone, grace)
end

-- Fires an arrow from the player along `angle` (a pico-8 turn, 0..1) at
-- the player's current power level, scaled by `force` (analog stick
-- tilt: 1 = the power level's full launch speed, so full tilt keeps the
-- maximum). `kind` selects the arrow type ("normal", "rope" or
-- "spirit"; the spirit is fired as a recoil-launch instead of an
-- arrow). Evicts a stuck arrow to make room when the quiver is full
-- (releasing its key first, if any).
--
-- The GUN rides the quiver: firing a normal arrow while a collected
-- gun is held launches the gun itself as the projectile (kind "gun"),
-- consumed by the shot: it flies like an arrow (slightly heavier) and
-- detonates on ANY contact exactly like the bomb arrow's blast --
-- "red bang on contact".
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
  -- the bomb arrow is a mobility tool like the spirit: firing it
  -- cuts an attached rope (its blast also knocks a line loose on impact)
  if kind == "bomb" and p.rope then p.rope = nil end
  -- the GUN is a mobility tool too: the blast knocks a line loose on
  -- impact, so the fire itself cuts the rope (the blast also does)
  if p.guns and p.guns > 0 and kind == "normal" and p.rope then
    p.rope = nil
  end
  -- a spirit is a recoil-launch, not an arrow: no quiver, no keys, no
  -- stick, no projectile. Its once-per-landing charge lives inside
  -- Spirit.fire: a dry bow clicks and does nothing at all (the rope
  -- cut travels with the fling, never with a click)
  if kind == "spirit" then
    Spirit.fire(ctx, angle, force)
    return
  end
  -- a held gun turns the NEXT normal shot into the gun itself: it
  -- leaves the bow as the projectile and detonates on any contact
  local gun_shot = false
  if kind == "normal" and p.guns and p.guns > 0 then
    gun_shot = true
    p.guns = p.guns - 1
  end
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
  if gun_shot then
    -- the gun is heavier than an arrow: it launches a touch slower
    spd = spd * config.gun.speed_scale
  end
  local arrow = {
    x = p.x + p.w/2, y = p.y + p.h/2,
    vx = dx*spd, vy = dy*spd,
    active = true, stuck = false, bounced = 0,
    sdx = dx, sdy = dy, spin = 0, lt = cfg.lifetime,
    kind = kind,
    traveled = 0,  -- rope arrows expire after config.rope.max_range of flight
  }
  if gun_shot then arrow.kind = "gun" end
  -- a fired arrow takes the player's carried key along; the player can
  -- grab it back on contact once the short cooldown lapses (the arrow
  -- spawns inside the player, so without it the handoff would undo
  -- itself the same step). Rope, bomb and gun shots never carry keys:
  -- a blast or a missed anchor must not eat a puzzle key.
  if p.key and kind ~= "rope" and kind ~= "bomb" and not gun_shot then
    arrow.key     = p.key
    arrow.grab_cd = cfg.grab_cooldown
    p.key = nil
  end
  table.insert(ents.arrows, arrow)
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
    if a.dying <= 0 or world:solid_at(nx, ny) then
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

    if world:solid_for_arrow(nx, ny) then
      -- bomb arrows and gun shots detonate on any surface: bounce walls
      -- (which would reflect other arrows) and solid terrain alike
      if a.kind == "bomb" or a.kind == "gun" then
        Arrows.detonate_bomb(ctx, nx, ny)
        a.active = false
        return
      end
      local hx = world:solid_for_arrow(nx, a.y)
      local hy = world:solid_for_arrow(a.x, ny)
      -- a bounce surface reflects the arrow instead of letting it embed
      -- (a tile flagged `bounce`, a moving block, a closed door)
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
        -- the tip goes IN: embed_px past the face, so the arrow reads as
        -- buried in the surface (the terrain pass draws over that buried
        -- length) instead of resting a few px clear of it
        local embed = cfg.embed_px
        if hx then
          -- the wall face is still recorded exactly as before: the perch
          -- and its hug read it, and the tip no longer sits at it
          a.face = a.vx > 0 and math.floor(nx / tw) * tw
                           or (math.floor(nx / tw) + 1) * tw
          a.x = a.face + (a.vx > 0 and embed or -embed)
        else
          a.x = nx
        end
        if hy then
          a.y = (a.vy > 0) and (math.floor(ny / tw) * tw + embed)
                            or ((math.floor(ny / tw) + 1) * tw - embed)
        else
          a.y = ny
        end
        if a.kind == "rope" then
          -- the rope anchors here: the tip freezes in the surface it
          -- struck
          a.anchored = true
        end
        if not hx and a.key and not a.key.used then
          -- floor/ceiling hit: the key poofs back into the world
          Particles.poof(ents, a.x, a.y)
          a.key.taken = false
          a.key = nil
        end
        -- an arrow burying itself in terrain is noise: enemies nearby
        -- hear the thunk and go look (no sight needed)
        notify_arrow_contact(ctx, a, a.x, a.y)
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

    -- key pickup by arrow tip (rope, bomb and gun shots never carry
    -- keys: a blast must not eat a puzzle key); the pad grows the
    -- key's tile so a near-miss still snags it
    if not a.key and a.kind ~= "rope" and a.kind ~= "bomb" and a.kind ~= "gun" then
      local pad = config.keys.pickup_pad
      local art = ctx.config.art_size
      for _, k in ipairs(ents.keys) do
        if not k.taken
        and nx >= k.x-pad and nx < k.x+art+pad
        and ny >= k.y-pad and ny < k.y+art+pad then
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
      local art = ctx.config.art_size
      for _, w in ipairs(ents.winches) do
        if nx >= w.x-pad and nx < w.x+art+pad
        and ny >= w.y-pad and ny < w.y+art+pad then
          local p = ctx.player
          p.rope = nil      -- a winch replaces any rope, and the rope_cd
          p.rope_cd = 0     -- grace: the pull is immediate
          -- the throw direction is carried from the entry side: the
          -- unit vector toward the winch now, refreshed by the reel
          -- while the player is still outside the pass radius, so an
          -- overshoot past the centre can never invert the throw
          local wcx, wcy = w.x + art/2, w.y + art/2
          local edx, edy = wcx - p.x - p.w/2, wcy - p.y - p.h/2
          local d = math.sqrt(edx*edx + edy*edy)
          if d > 0 then
            edx, edy = edx / d, edy / d
          else
            edx, edy = a.sdx or 0, a.sdy or 0  -- degenerate: arrow travel
          end
          p.winch = { ent = w, dir_x = edx, dir_y = edy }
          p.arrow_stand = nil  -- the winch owns the body from here
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

    -- arrow strikes a pusher: the arrow is consumed (poof into the
    -- device, like the winch capture) and the device fires its variant
    -- shove (the updraft's straight-up column or the outdraft's
    -- up-and-away cone). Bomb arrows detonate their own blast at the
    -- strike point first, so the two shoves stack.
    for _, pu in ipairs(ents.pushers) do
      local art = ctx.config.art_size
      if nx >= pu.x and nx < pu.x+art and ny >= pu.y and ny < pu.y+art then
        Particles.poof(ents, nx, ny)
        a.active = false
        if a.kind == "bomb" then
          Arrows.detonate_bomb(ctx, nx, ny)
        end
        Arrows.trigger_pusher(ctx, pu)
        return
      end
    end

    -- arrow strikes a moving block (movers.lua): recessed for arrows
    -- (solid_for_arrow answers false inside the block), so the tip
    -- enters any tile of the current box and strikes. A trigger mover
    -- fires and runs its line (the arrow consumed, pusher-style); an
    -- auto mover just eats the arrow. Bomb arrows detonate their own
    -- blast at the strike point first, so the two forces stack.
    for _, mv in ipairs(ents.movers) do
      if nx >= mv.bx and nx < mv.bx + mv.bw
      and ny >= mv.by and ny < mv.by + mv.bh then
        Particles.poof(ents, nx, ny)
        a.active = false
        if a.kind == "bomb" then
          Arrows.detonate_bomb(ctx, nx, ny)
        end
        Movers.trigger(ctx, mv)
        return
      end
    end

    -- arrow strikes a switch: toggle it and re-evaluate its group's doors
    -- (one toggle per pass through a switch's tile). Springs no longer
    -- answer switch strikes: they are landing pads now (Player.physics).
    local in_switch = false
    for _, s in ipairs(ents.switches) do
      local art = ctx.config.art_size
      if nx >= s.x and nx < s.x+art and ny >= s.y and ny < s.y+art then
        in_switch = true
        if a.last_switch ~= s then
          a.last_switch = s
          -- every strike flips the switch: doors re-evaluate; only
          -- switches flagged "phase" flip the level's phase tiles
          s.on = not s.on
          Interactables.eval_switch_doors(ents, s.g)
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
      local art = ctx.config.art_size
      for _, lock in ipairs(ents.locks) do
        if not lock.triggered
        and Interactables.key_fits_lock(a.key, lock)
        and nx >= lock.x-pad and nx < lock.x+art+pad
        and ny >= lock.y-pad and ny < lock.y+art+pad then
          Interactables.trigger_lock(ents, lock)
          a.key.used = true  -- consumed; will not respawn if arrow expires
          a.key      = nil
          break
        end
      end
    end

    -- enemy hit: any arrow tip kills the enemy (blood, instant removal);
    -- a bomb arrow kills the touched one first, then its blast shoves
    -- everything nearby -- a bomb jump off an enemy
    for i, e in ipairs(ents.enemies) do
      if nx >= e.x and nx < e.x+e.w and ny >= e.y and ny < e.y+e.h then
        Particles.blood(ents, nx, ny, a.vx, a.vy)
        -- ...and the same blood leaves the far side, thrown along the
        -- shot: the entry spray above comes back out the way the arrow
        -- came in, this one says it went THROUGH. The walk out follows
        -- the arrow's LIVE heading (its arc has turned since the bow
        -- released it), not the launch line it froze on.
        local sh = math.sqrt(a.vx*a.vx + a.vy*a.vy)
        if sh == 0 then sh = 1 end
        local ex, ey = exit_point(e, nx, ny, a.vx / sh, a.vy / sh)
        Particles.blood_exit(ents, ex, ey, a.vx, a.vy)
        table.remove(ents.enemies, i)
        -- the laser rifleman drops its gun at the death spot: the
        -- late-game pickup (walk into it to carry one explosive shot)
        if e.type == "laser" then
          table.insert(ents.guns, { x = e.x, y = e.y, taken = false })
        end
        -- hitstop: a few frozen frames on the kill read the impact
        if ctx.freeze then
          ctx.freeze = math.max(ctx.freeze, config.player.freeze_steps)
        else
          ctx.freeze = config.player.freeze_steps
        end
        if a.kind == "gun" then
          -- the gun is consumed by the hit and detonates (the red
          -- bang): enemy kill + the shared blast
          Arrows.detonate_bomb(ctx, nx, ny)
          a.active = false
          return
        end
        if a.kind == "bomb" then
          -- the bomb arrow kills the touched one first, then its blast
          -- shoves everything nearby -- a bomb jump off an enemy
          Arrows.detonate_bomb(ctx, nx, ny)
          a.active = false
          return
        end
        a.active = false
        return
      end
    end

    -- rocket hit: any arrow tip detonates the rocket
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

    -- bomb hit: any arrow tip detonates the thrown
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
    elseif ctx.world:in_room(a.x, a.y) then
      Arrows.step_one(ctx, a)
    end  -- arrows beyond the active room hang frozen (off-screen)
  end
end

-- The perch's precondition: the arrow really is embedded in a vertical
-- wall. Only a horizontal hit records `a.face` at stick time (see
-- step_one), so the face alone rules out floor and ceiling arrows --
-- including the shallow downward shots that used to snag a player
-- walking over them and invent a wall face out of their own x. The
-- wall must also still be standing: a few px past the face, the same
-- embedding test a rope anchor gets (Player.rope_step), so a door
-- opening under an arrow drops the perch instead of leaving it
-- hanging in the gap.
local function wall_perch(a, world)
  if not a.face then return false end
  return world:solid_for_arrow(a.face + (a.sdx > 0 and 4 or -4), a.y)
end

-- Stuck arrows in vertical walls catch the player's fall: an arrow
-- stand is a PERCH, not ground. Landing on one enters `p.arrow_stand`:
-- the feet pin to the arrow's band AND the body is pulled flush against
-- the wall (the hug: any catch within a tile of the face snaps the body
-- against it, so the perch only exists as a wall-hug), but `p.gr` stays
-- false and movement input is ignored (src/player.lua). The perch is
-- the wall's rest state; the only exits are a jump (the wall leap, the
-- same buffered launch as a ground jump), the arrow's destruction, the
-- wall going away under it, or a shove knocking the body loose. A
-- catch requires the body to sit within a tile of the wall face --
-- land farther out and the fall passes the arrow by (no perch away
-- from the wall). Aim is clamped away from the wall while perched
-- (Player.aim_step).
--
-- Only arrows embedded in a vertical wall are platforms at all
-- (wall_perch): an arrow buried in a floor or a ceiling is never one,
-- so the body walks straight over it.
function Arrows.check_platforms(ctx)
  local p, ents, world = ctx.player, ctx.ents, ctx.world
  local tw = ctx.config.tile_size
  if p.vy < 0 then return end
  -- maintain an existing perch first (the arrow may have been removed,
  -- or the wall it leaned on may have opened)
  if p.arrow_stand then
    local a = p.arrow_stand.arrow
    if not a or not a.active or not a.stuck or not wall_perch(a, world) then
      p.arrow_stand = nil
    else
      local by = p.y + p.h
      if by >= a.y - 2 and by <= a.y + 8 then
        p.y = a.y - p.h
        p.vy = 0
      else
        p.arrow_stand = nil
      end
    end
    if p.arrow_stand then return end  -- still perched: land check done
  end
  for _, a in ipairs(ents.arrows) do
    if a.stuck and a.active and a.kind ~= "rope"
    and wall_perch(a, world) then
      -- the wall face was recorded at stick time (the retracted tip no
      -- longer sits inside the wall tile)
      local ay = a.y
      local by = p.y + p.h
      if by >= ay - 2 and by <= ay + 8 then
        local ax1, ax2
        local wx = a.face
        if a.sdx > 0 then
          ax1, ax2 = wx - 14, wx + 4
        else
          ax1, ax2 = wx - 4, wx + 14
        end
        if p.x + p.w > ax1 and p.x < ax2 then
          -- the catch hugs: the body is pulled flush against the wall
          -- face (rx) when it lands within a tile of it; farther out
          -- the fall passes the arrow by (no perch off the wall)
          local rx = (a.sdx > 0) and (wx - p.w) or wx
          local dx = rx - p.x
          if p.x == rx or (dx > -tw and dx < tw) then
            p.x = rx
            p.arrow_stand = { arrow = a, side = a.sdx > 0 and 1 or -1 }
            p.y  = ay - p.h
            p.vy = 0
            p.coy = 0
            return
          end
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
    elseif not world:in_room(a.x, a.y) then
      -- beyond the active room: hang frozen (off-screen)
    else
      a.vy = a.vy + cfg.gravity * dt
      local nsub = math.max(1,
        math.ceil((math.abs(a.vx) + math.abs(a.vy)) * dt / cfg.substep_pixels))
      local sx, sy = a.vx * dt / nsub, a.vy * dt / nsub
      for _ = 1, nsub do
        local nx = a.x + sx
        local ny = a.y + sy
        if world:solid_for_arrow(nx, ny) then
          -- an enemy dart burying itself in terrain throws scorched
          -- chunks off the surface (the player's own arrows hit quietly
          -- by design; the enemies' impacts are set pieces)
          Particles.scorch(ents, a.x, a.y, a.vx, a.vy)
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
