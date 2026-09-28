-- Rope arrow tests (deterministic, headless; requires LuaJIT).
--
-- Covers the rope/grapple arrow:
--   1. attach + hang: a stuck rope arrow attaches the player, who then
--      hangs at the rope length instead of falling
--   2. pendulum swing: horizontal speed converts into a swing that
--      carries the player across the anchor, staying within rope length
--   3. jump detaches and preserves velocity (no buffered jump)
--   4. winching: up shortens, down lengthens, within the clamps
--   5. rope arrows poof at max_range in flight; normal arrows do not
--   6. rope arrows are not platforms; normal stuck arrows still are
--   7. the swap button cycles arrow types and firing produces the kind
--   8. losing the anchor (arrow removed / wall opened) releases the rope
--   9. spirit shots fling the player opposite the aim (a burst of
--      particles, no projectile), cut an attached rope and bypass the
--      arrow quiver entirely
--
-- Usage (from the project root): luajit tests/rope_test.lua

local Harness = dofile("tests/harness.lua")

local PASS, FAIL = 0, 0
local function assert_true(cond, msg)
  if cond then
    PASS = PASS + 1
  else
    FAIL = FAIL + 1
    print("FAIL: " .. msg)
  end
end

local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

-- Sets held keys for exactly one step (a clean press edge), then a
-- release step so the next tap's edge fires.
local function tap(env, key)
  local kd = env.TWANG_TEST.keys_down
  kd[key] = true
  run_steps(env, 1)
  kd[key] = false
  run_steps(env, 1)
end

local function place_player(g, x, y)
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- Builds a ceiling block (art column 6, art row 8 -> x=96..112,
-- y=128..144; its four 8px sub-cells) in the open area right of the
-- spawn wall and returns the world.
local function rig_ceiling(g)
  local w = g.ctx.world
  local solid_id = w:tile(0, 28)  -- the spawn-area wall/floor sub-tile id
  for dc = 0, 1 do
    for dr = 0, 1 do
      w:set_tile(6*2 + dc, 8*2 + dr, solid_id)
    end
  end
  return w
end

-- A rope arrow stuck in the underside of the rig ceiling: tip at the
-- bottom face (y=144), travelling up at stick time.
local function rig_rope_arrow(g)
  local a = {
    x = 104, y = 144, vx = 0, vy = -2,
    active = true, stuck = true, bounced = 0,
    sdx = 0, sdy = -1, spin = 0, lt = 30000,
    kind = "rope", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

local function rope_dist(g)
  local p, a = g.ctx.player, g.ctx.player.rope.arrow
  local cx, cy = p.x + p.w/2, p.y + p.h/2
  return math.sqrt((cx - a.x)^2 + (cy - a.y)^2)
end

-- ==== 1. attach + hang ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  local a = rig_rope_arrow(g)
  -- directly below the anchor, 54px of rope
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "the player attached to the anchored rope arrow")
  assert_true(p.rope.arrow == a, "the rope references the anchored arrow")
  local length = p.rope.length
  assert_true(math.abs(length - 54) < 3,
    "rope length starts at the player-anchor distance (got " .. length .. ")")
  local worst = 0
  for _ = 1, 60 do
    run_steps(env, 1)
    local d = rope_dist(g)
    if d > worst then worst = d end
  end
  assert_true(worst <= length + 3,
    "the player never falls past the rope length (max " .. worst .. ")")
  local cy = p.y + p.h/2
  assert_true(math.abs(cy - (144 + length)) < 6,
    "the player hangs at the rope's end (centre y " .. cy .. ")")
end

-- ==== 2. pendulum swing carries the player across the anchor ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  rig_rope_arrow(g)
  -- offset left of the anchor with outward speed: swings across to the right
  place_player(g, 76, 180)
  p.vx = 3
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the swing test")
  local length = p.rope.length
  local crossed, worst = false, 0
  for _ = 1, 150 do
    run_steps(env, 1)
    local a = p.rope and p.rope.arrow
    if not a then break end
    local rx = (p.x + p.w/2) - a.x
    if rx > 4 then crossed = true end
    local d = rope_dist(g)
    if d > worst then worst = d end
  end
  assert_true(crossed, "the swing carried the player across the anchor")
  assert_true(worst <= length + 3,
    "the swing never exceeded the rope length (max " .. worst .. ")")
end

-- ==== 3. jump releases the rope, preserving velocity ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  rig_rope_arrow(g)
  place_player(g, 76, 180)
  p.vx = 3
  run_steps(env, 20)  -- mid-swing
  assert_true(p.rope ~= nil, "attached before the detach test")
  local vx0, vy0 = p.vx, p.vy
  tap(env, "x")  -- jump
  assert_true(p.rope == nil, "jumping released the rope")
  -- the detach preserves velocity; the walk motor's air damping still
  -- applies after it (deceleration * air_deceleration_scale per step,
  -- two steps across the tap), so the window rides that decay
  assert_true(math.abs(p.vx - vx0) < 1.2,
    "horizontal velocity survived the detach (was " .. vx0 .. ", now " .. p.vx .. ")")
  assert_true(p.vy > vy0 - 0.02,
    "vertical velocity survived the detach (was " .. vy0 .. ", now " .. p.vy .. ")")
  -- no buffered jump: vy must not have been kicked upward
  assert_true(p.vy > -2, "no jump fired on detach (vy " .. p.vy .. ")")
  -- the released arrow does not re-grab the player
  run_steps(env, 10)
  assert_true(p.rope == nil, "the released arrow never re-attaches")
end

-- ==== 4. winching the rope in and out ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  rig_rope_arrow(g)
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the winch test")
  local l0 = p.rope.length
  local kd = env.TWANG_TEST.keys_down
  kd.up = true
  run_steps(env, 10)
  kd.up = false
  local l1 = p.rope.length
  assert_true(l1 < l0 - 2, "holding up shortens the rope (" .. l0 .. " -> " .. l1 .. ")")
  kd.down = true
  run_steps(env, 20)
  kd.down = false
  local l2 = p.rope.length
  assert_true(l2 > l1 + 2, "holding down lengthens the rope (" .. l1 .. " -> " .. l2 .. ")")
  assert_true(l2 <= g.ctx.config.rope.max_length + 0.01,
    "the rope clamps at max_length (got " .. l2 .. ")")
end

-- ==== 5. rope arrows poof at max range; normal arrows fly on ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 80, 200)
  g.ctx.config.rope.max_range = 24
  table.insert(g.ctx.ents.arrows, {
    x = 80, y = 154, vx = 8, vy = 0, active = true, stuck = false,
    bounced = 0, sdx = 1, sdy = 0, spin = 0, lt = 300,
    kind = "rope", traveled = 0,
  })
  run_steps(env, 5)
  assert_true(#g.ctx.ents.arrows == 0,
    "the rope arrow expired at max range")
  assert_true(p.rope == nil, "no rope attached from a missed arrow")
  table.insert(g.ctx.ents.arrows, {
    x = 80, y = 154, vx = 8, vy = 0, active = true, stuck = false,
    bounced = 0, sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal",
  })
  run_steps(env, 5)
  assert_true(#g.ctx.ents.arrows == 1 and g.ctx.ents.arrows[1].active,
    "a normal arrow flies past the rope's max range unaffected")
end

-- ==== 6. rope arrows are not platforms; normal arrows still are ====
-- (both scenarios sit the player clear of the spawn area's left wall:
-- an automatic wall-slide now catches falls against solid walls)
do
  -- rope variant: the player falls straight past the stuck arrow
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  table.insert(g.ctx.ents.arrows, {
    x = 10, y = 200, vx = 0, vy = 0, active = true, stuck = true,
    bounced = 0, sdx = 2, sdy = 0, spin = 0, lt = 30000,
    kind = "rope", traveled = 10, face = 16, rope_taken = true,
  })
  place_player(g, 80, 180)
  p.vy = 6
  run_steps(env, 6)
  assert_true(p.y > 200, "the player fell past the rope arrow (y " .. p.y .. ")")
  assert_true(not (p.gr and p.y == 188), "the rope arrow gave no platform")
end
do
  -- normal variant: the stuck arrow catches the falling player as a
  -- PERCH (not ground): feet pinned to the arrow, no coyote, no walk
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  table.insert(g.ctx.ents.arrows, {
    x = 80, y = 200, vx = 0, vy = 0, active = true, stuck = true,
    bounced = 0, sdx = 2, sdy = 0, spin = 0, lt = 30000,
    kind = "normal", face = 86,
  })
  place_player(g, 80, 180)
  p.vy = 6
  run_steps(env, 6)
  assert_true(p.arrow_stand ~= nil and p.y == 188,
    "a normal stuck arrow still catches the fall as a perch (y " .. p.y .. ")")
  assert_true(not p.gr and p.vy == 0,
    "a perch is not ground: no coyote, no walk, the fall just stops")
end

-- ==== 7. the swap button cycles arrow kind; firing honours it ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  -- the menu's bomb/shock hide toggle defaults on: unhide for the full
  -- four-kind cycle under test here
  g.settings.no_special = false
  place_player(g, 80, 212)  -- standing on the spawn-area floor
  assert_true(p.arrow_kind == "normal", "starts with normal arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "rope", "swap cycled to rope arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "spirit", "swap cycled to spirit shots")
  tap(env, "c")
  assert_true(p.arrow_kind == "bomb", "swap cycled to bomb arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "normal", "swap cycled back to normal arrows")
  -- fire a rope arrow: hold aim, then release
  tap(env, "c")
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 2)
  kd.z = false
  run_steps(env, 1)
  assert_true(#g.ctx.ents.arrows == 1, "the bow fired on aim release")
  local a = g.ctx.ents.arrows[1]
  assert_true(a.kind == "rope", "the fired arrow is a rope arrow")
  assert_true(a.traveled > 0, "the rope arrow tracks its flight range")
end

-- ==== 8. losing the anchor releases the rope ====
do
  -- arrow removed
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  local a = rig_rope_arrow(g)
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the anchor-loss test")
  a.active = false
  run_steps(env, 1)
  assert_true(p.rope == nil, "removing the anchor arrow releases the rope")
end
do
  -- wall opened under the anchor (e.g. a door)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local w = rig_ceiling(g)
  local a = rig_rope_arrow(g)
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the wall-open test")
  w:set_tile(12, 16, 0)
  w:set_tile(13, 16, 0)
  w:set_tile(12, 17, 0)
  w:set_tile(13, 17, 0)
  run_steps(env, 1)
  assert_true(p.rope == nil, "opening the wall under the anchor releases the rope")
end

-- ==== 9. spirit shots fling the player opposite the aim ====
-- Aims by holding aim one step (enters aim mode), forcing aim_angle
-- directly, then releasing: the release step fires along that angle.
-- One fling per landing on solid ground, and an upward fling IS a
-- second jump: it always rises a full jump's height even through a
-- full-speed fall.
local function fire_at(env, g, angle)
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 1)
  g.ctx.player.aim_angle = angle
  kd.z = false
  run_steps(env, 1)
end

local function select_spirit(env)
  env.TWANG_TEST.game.settings.no_special = false  -- the spirit is hidden by default
  tap(env, "c")
  tap(env, "c")
end

do
  -- firing straight down flings the player straight up: the fling is
  -- instant, no wave to wait for, and the fire spawns NO projectile
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 180)  -- mid-air: the fling needs no ground, it
                             -- is instant (unlike the old bounce-back)
  p.gr = false
  select_spirit(env)
  assert_true(p.arrow_kind == "spirit", "spirit shots equipped")
  local vy0 = p.vy
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.arrows == 0, "the spirit fired no arrow")
  assert_true(p.vy < vy0 - 9,
    "a downward shot flung the player upward (vy " .. p.vy .. ")")
  assert_true(not p.gr and p.j_frames == 0,
    "the fling took the body airborne with the jump cut")
  -- the fire left the burst behind: ghostly particles and nothing else
  -- (the ghostly blue itself is render-time while the kind is equipped)
  assert_true(#g.ctx.ents.particles > 0, "the burst left particles")
  assert_true(#g.ctx.ents.booms == 0, "no flash ring and no boom: particles only")
  assert_true(p.winch_grace ~= nil and p.winch_grace > 0,
    "the fling rides the shove-grace window")
  assert_true(p.spirit_armed == false, "the fling burned its one charge")
end
do
  -- aiming right flung the player left, additive with the body's
  -- motion: the +2 running start carries (and the impulse never runs
  -- PAST its own strength alone)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cfg = env.require("src.config").spirit
  place_player(g, 100, 180)
  p.gr = false
  select_spirit(env)
  p.vx = 2
  fire_at(env, g, 0.0)   -- md power, force 1.0 (keyboard has no tilt)
  assert_true(p.vx < 0,
    "aiming right flung the player left (vx " .. p.vx .. ")")
  assert_true(p.vx > -cfg.push[2] - 0.01,
    "the impulse is additive: never past its own strength alone (vx "
    .. p.vx .. ")")
end
do
  -- the power level scales the fling: hi pushes harder than md (the
  -- spirit re-arms between shots: the charge is one per landing)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cfg = env.require("src.config").spirit
  local Spirit = env.require("src.spirit")
  place_player(g, 100, 180)
  p.gr = false
  select_spirit(env)
  fire_at(env, g, 0.0)
  local md = p.vx
  p.spirit_armed = true   -- re-arm for the hi-power comparison shot
  p.vx, p.vy, p.winch_grace = 0, 0, nil
  p.aim_angle, p.aim_power, p.aim_force = 0.0, 3, 1.0
  Spirit.fire(g.ctx, 0.0, 1.0)
  local hi = p.vx
  assert_true(math.abs(hi) > math.abs(md),
    "hi power flings harder than md (" .. hi .. " vs " .. md .. ")")
  -- the analog force floor: a deadzone-edge tilt flings at the floor
  -- share, never zero
  p.spirit_armed = true
  p.vx, p.vy, p.winch_grace = 0, 0, nil
  p.aim_force = cfg.min_force_scale
  Spirit.fire(g.ctx, 0.0, cfg.min_force_scale)
  assert_true(math.abs(math.abs(p.vx) - cfg.push[3] * cfg.min_force_scale) < 0.01,
    "a light tilt flings at the floor share (vx " .. p.vx .. ")")
end
do
  -- firing a spirit releases an attached rope (mobility tool)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  rig_rope_arrow(g)
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the spirit-release test")
  select_spirit(env)
  fire_at(env, g, 0.25)
  assert_true(p.rope == nil, "the spirit fire released the rope")
end
do
  -- the spirit bypasses the arrow quiver entirely (no evict, no spawn)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 180)
  p.gr = false
  select_spirit(env)
  for i = 1, 3 do
    local n_arrows = #g.ctx.ents.arrows
    p.spirit_armed = true   -- the charge refreshes only on landings; the
                            -- quiver test just re-arms directly
    fire_at(env, g, 0.25)
    assert_true(#g.ctx.ents.arrows == n_arrows,
      "fire " .. i .. " spawned no arrow (the quiver is untouched)")
  end
end
do
  -- the swap cycle honours the spirit: a third tap lands on it and a
  -- fourth passes it to the bomb
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  g.settings.no_special = false
  tap(env, "c")
  assert_true(p.arrow_kind == "rope", "swap cycled to rope arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "spirit", "swap cycled to spirit shots")
  tap(env, "c")
  assert_true(p.arrow_kind == "bomb", "swap cycled past the spirit to bombs")
  tap(env, "c")
  assert_true(p.arrow_kind == "normal", "swap cycled back to normal arrows")
end

do
  -- ONE fling per stretch of air: a spent bow clicks (no fling, no
  -- burst, no rope cut) and landing on solid ground refills the
  -- charge; a plain jump takes the charge airborne without burning it
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 180)
  p.gr = false
  select_spirit(env)
  fire_at(env, g, 0.25)
  assert_true(p.spirit_armed == false, "the fling spent the charge")
  -- now dry: the next aim-and-release does nothing at all -- no fling
  -- against the fall, no burst
  local n0 = #g.ctx.ents.particles
  local vy0 = p.vy
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.particles == n0, "a dry bow bursts nothing")
  -- gravity drifts the fall down during the two aim steps; the fling
  -- would have launched: assert it never went up
  assert_true(p.vy > vy0 - 0.01, "a dry bow flings nothing")
  -- drawing the dry click stays sane, then land to refill
  local landed = false
  for _ = 1, 60 do
    run_steps(env, 1)
    if p.gr then landed = true break end
  end
  assert_true(landed, "the flung player came back to solid ground")
  assert_true(p.spirit_armed, "landing on solid ground refilled the charge")
  -- a jump takes the charge airborne without burning it (held, so the
  -- short hop is a real jump and stays airborne across the window)
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 4)
  assert_true(not p.gr, "the player jumped back into the air")
  env.TWANG_TEST.keys_down.x = nil
  assert_true(p.spirit_armed, "a jump did not spend or lose the charge")
  fire_at(env, g, 0.25)
  assert_true(not p.spirit_armed, "the airborne shot fired and spent it")
end
do
  -- the second jump: an upward fling always rises a full jump's worth
  -- above the fired point, even through a full-speed fall. Fired via
  -- Spirit.fire directly so the knock math is exact (the aim-release
  -- path is covered above)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local C = env.require("src.config")
  local Spirit = env.require("src.spirit")
  place_player(g, 100, 180)
  p.gr = false
  p.vy = C.physics.max_fall_speed
  Spirit.fire(g.ctx, 0.25, 1.0)   -- md power (the fresh aim power), straight down
  local tick = 30 / C.sim.rate  -- one integration tick, in world-time steps
  local floor_vy = C.player.jump_velocity - C.physics.gravity * tick
  assert_true(math.abs(p.vy - floor_vy) < 1e-6,
    "the fall was paid for: the launch lands on the floor speed (vy "
    .. p.vy .. ", floor " .. floor_vy .. ")")
  -- the rise from the fired point: a whole jump's ballistic apex (the
  -- sim's discrete integration lands ~2px under the continuous value)
  local fired_y = p.y
  local min_y, rose = fired_y, false
  for _ = 1, 40 do
    run_steps(env, 1)
    if p.y < min_y then min_y = p.y end
    if p.vy >= 0 then rose = true break end
  end
  assert_true(rose and (fired_y - min_y) >= 31,
    "the fling rose a full jump's height through the fall (rise "
    .. (fired_y - min_y) .. ")")
end
do
  -- the guarantee holds for DIAGONAL aims too (the vertical share
  -- stretches, the horizontal share keeps its shot), and it is a floor
  -- only: a strong shot from a mild fall stays stronger
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local C = env.require("src.config")
  local Spirit = env.require("src.spirit")
  local tick = 30 / C.sim.rate  -- one integration tick, in world-time steps
  local floor_vy = C.player.jump_velocity - C.physics.gravity * tick
  place_player(g, 100, 180)
  p.gr = false
  p.vy = C.physics.max_fall_speed
  Spirit.fire(g.ctx, 0.125, 1.0)  -- 45 degrees down-forward
  assert_true(math.abs(p.vy - floor_vy) < 1e-6,
    "a diagonal aim still guarantees the second-jump rise (vy " .. p.vy .. ")")
  assert_true(p.vx < -8.5, "the diagonal's horizontal knock stayed (vx "
    .. p.vx .. ")")
  -- a strong shot from a mild fall: no clamp, the edge survives
  p.vx, p.vy, p.winch_grace = 0, 4, nil
  p.spirit_armed = true
  Spirit.fire(g.ctx, 0.25, 1.0)
  assert_true(math.abs(p.vy - (4 - C.spirit.push[2])) < 1e-6,
    "a strong shot from a mild fall keeps its edge (vy " .. p.vy .. ")")
end
do
  -- a LEVEL fire grants no rise: the fall carries the body (a lateral
  -- fling is exactly that; the second jump rides below-level aims)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local C = env.require("src.config")
  local Spirit = env.require("src.spirit")
  place_player(g, 100, 180)
  p.gr = false
  p.vy = C.physics.max_fall_speed
  Spirit.fire(g.ctx, 0.0, 1.0)    -- straight right -> flung straight left
  assert_true(math.abs(p.vy - C.physics.max_fall_speed) < 1e-6,
    "a level fire granted no rise (vy " .. p.vy .. ")")
  assert_true(p.vx < -12, "and still flung the body sideways (vx "
    .. p.vx .. ")")
end

print(("rope tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
