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
--   9. shockwave pulses shove what they touch (enemies, the player on
--      bounce-backs, enemy projectiles) and fizzle at max range; the
--      fire is recoil-free and bypasses the arrow quiver
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

-- Builds a ceiling block (tile column 6, row 8 -> x=96..112, y=128..144)
-- in the open area right of the spawn wall and returns the world.
local function rig_ceiling(g)
  local w = g.ctx.world
  local solid_id = w:tile(0, 14)  -- the spawn-area wall/floor tile id
  w:set_tile(6, 8, solid_id)
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
  assert_true(math.abs(p.vx - vx0) < 0.4,
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
  place_player(g, 16, 180)
  p.vy = 6
  run_steps(env, 6)
  assert_true(p.y > 200, "the player fell past the rope arrow (y " .. p.y .. ")")
  assert_true(not (p.gr and p.y == 188), "the rope arrow gave no platform")
end
do
  -- normal variant: the stuck arrow catches the falling player
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  table.insert(g.ctx.ents.arrows, {
    x = 10, y = 200, vx = 0, vy = 0, active = true, stuck = true,
    bounced = 0, sdx = 2, sdy = 0, spin = 0, lt = 30000,
    kind = "normal", face = 16,
  })
  place_player(g, 16, 180)
  p.vy = 6
  run_steps(env, 6)
  assert_true(p.gr and p.y == 188,
    "a normal stuck arrow still acts as a platform (y " .. p.y .. ")")
end

-- ==== 7. the swap button cycles arrow kind; firing honours it ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 80, 212)  -- standing on the spawn-area floor
  assert_true(p.arrow_kind == "normal", "starts with normal arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "rope", "swap cycled to rope arrows")
  tap(env, "c")
  assert_true(p.arrow_kind == "shockwave", "swap cycled to shockwave pulses")
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
  w:set_tile(6, 8, 0)
  run_steps(env, 1)
  assert_true(p.rope == nil, "opening the wall under the anchor releases the rope")
end

-- ==== 9. shockwave pulses shove what they touch ====
-- Aims by holding aim one step (enters aim mode), forcing aim_angle
-- directly, then releasing: the release step fires along that angle.
local function fire_at(env, g, angle)
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 1)
  g.ctx.player.aim_angle = angle
  kd.z = false
  run_steps(env, 1)
end

local function select_shockwave(env)
  tap(env, "c")
  tap(env, "c")
end

local function wave(x, y, vx, vy)
  return {
    x = x, y = y, vx = vx, vy = vy, r = 3, traveled = 0,
    active = true, bounced = 0, pushed = {},
  }
end

do
  -- airborne over a tile below: a straight-down shot bounces back up
  -- and flings the player upward (the wave itself flies on and fizzles)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local w = g.ctx.world
  place_player(g, 100, 175)  -- mid-air above the tile, with room for
                             -- the wave's centre to clear the player's
                             -- box before the bounce-back
  p.gr = false
  w:set_tile(6, 13, 10)      -- tile below the player
  select_shockwave(env)
  assert_true(p.arrow_kind == "shockwave", "shockwave pulses equipped")
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.shockwaves == 1
    and math.abs(g.ctx.ents.shockwaves[1].vx) < 0.01
    and g.ctx.ents.shockwaves[1].vy > 0,
    "the shockwave spawned downward")
  -- fall, bounce off the tile, and let the returning front sweep into
  -- the player: the shove lands mid-air, a few steps after firing
  local min_vy, airborne = p.vy, false
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.vy < min_vy then min_vy = p.vy end
    if not p.gr then airborne = true end
  end
  assert_true(min_vy < -6,
    "the bounce-back flung the player upward (min vy " .. min_vy .. ")")
  assert_true(airborne, "the flung player went airborne")
  run_steps(env, 20)
  assert_true(#g.ctx.ents.shockwaves == 0, "the wave fizzled at max range")
end
do
  -- a bounce against a surface flush with the player (a floor at their
  -- feet) shoves immediately: the reflected front is heading straight
  -- back through them, no exit-and-return wait needed
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 80, 212)  -- standing on the spawn-area floor
  run_steps(env, 2)
  assert_true(p.gr, "grounded for the floor-bounce launch test")
  select_shockwave(env)
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.shockwaves == 1, "the grounded fire spawned a wave")
  run_steps(env, 4)
  assert_true(p.vy < -6 and not p.gr,
    "the floor bounce launched the player (vy " .. p.vy .. ")")
end
do
  -- direct enemy hit: the enemy survives and is shoved (added velocity),
  -- the wave is not consumed (it flies on and fizzles at max range);
  -- a normal arrow into the same setup still kills
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 80, 212)  -- standing on the spawn-area floor, clear
  run_steps(env, 2)
  local e = {
    x = 140, y = 120, vx = 0, vy = 0, w = 12, h = 16,
    gr = false, facing = 1, type = "melee", home_x = 140, shoot_cd = 90,
    state = "patrol",
  }
  table.insert(g.ctx.ents.enemies, e)
  run_steps(env, 1)  -- the enemy is in open sky; it starts falling
  local n0 = #g.ctx.ents.enemies
  table.insert(g.ctx.ents.shockwaves, wave(e.x - 8, e.y + 8, 12, 0))
  run_steps(env, 1)
  assert_true(#g.ctx.ents.enemies == n0, "the shockwave did not kill the enemy")
  assert_true(e.vx > 0 and e.vy > 0, "the shove launched the enemy (vx "
    .. e.vx .. ", vy " .. e.vy .. ")")
  assert_true(#g.ctx.ents.shockwaves == 1,
    "the wave was not consumed by the shove")
  run_steps(env, 15)
  assert_true(#g.ctx.ents.shockwaves == 0, "the wave fizzled at max range")
end
do
  -- the front is a semicircle opening along travel: a target behind
  -- the wave's flat back edge is not swept (only what lies ahead of
  -- the wave gets bowled)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  place_player(g, 80, 212)
  run_steps(env, 2)
  local e = {
    x = 140, y = 120, vx = 0, vy = 0, w = 12, h = 16,
    gr = false, facing = 1, type = "melee", home_x = 140, shoot_cd = 90,
    state = "patrol",
  }
  table.insert(g.ctx.ents.enemies, e)
  run_steps(env, 1)
  table.insert(g.ctx.ents.shockwaves, wave(150, 124, 10, 0))
  run_steps(env, 1)
  assert_true(e.vx == 0,
    "a target behind the flat back edge was not swept (vx " .. e.vx .. ")")
end
do
  -- a normal arrow into the same setup still kills the enemy
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 80, 212)
  run_steps(env, 2)
  local e = {
    x = 140, y = 120, vx = 0, vy = 0, w = 12, h = 16,
    gr = false, facing = 1, type = "melee", home_x = 140, shoot_cd = 90,
    state = "patrol",
  }
  table.insert(g.ctx.ents.enemies, e)
  run_steps(env, 1)
  local n0 = #g.ctx.ents.enemies
  table.insert(g.ctx.ents.arrows, {
    x = e.x + 2, y = e.y + 4, vx = 4, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 2, sdy = 0, spin = 0, lt = 300, kind = "normal",
  })
  run_steps(env, 1)
  assert_true(#g.ctx.ents.enemies == n0 - 1, "the normal arrow still killed")
end
do
  -- a thrown bomb is knocked off course, not detonated
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  place_player(g, 80, 212)
  run_steps(env, 2)
  local b = { x = 140, y = 120, vx = 0, vy = 0, fuse = 90, active = true }
  table.insert(g.ctx.ents.bombs, b)
  table.insert(g.ctx.ents.shockwaves, wave(134, 120, 5, 0))
  run_steps(env, 1)
  assert_true(b.active, "the knocked bomb did not detonate")
  assert_true(b.vx > 0, "the shove flung the bomb (vx " .. b.vx .. ")")
end
do
  -- an enemy dart is deflected off course, still flying
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  place_player(g, 80, 212)
  run_steps(env, 2)
  local dart = { x = 140, y = 120, vx = 0, vy = 4, active = true }
  table.insert(g.ctx.ents.e_arrows, dart)
  table.insert(g.ctx.ents.shockwaves, wave(134, 120, 5, 0))
  run_steps(env, 1)
  assert_true(dart.active, "the deflected dart still flies")
  assert_true(dart.vx > 0, "the wave knocked the dart aside (vx "
    .. dart.vx .. ")")
end
do
  -- a hovering rocket is knocked away from the wave
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  place_player(g, 80, 212)
  run_steps(env, 2)
  local r = {
    x = 140, y = 120, hx = 0, hy = -1, state = "hover",
    climbed = 24, hover_t = 12, active = true, lt = 150, trail_t = 2,
    kx = 0, ky = 0,
  }
  table.insert(g.ctx.ents.rockets, r)
  table.insert(g.ctx.ents.shockwaves, wave(134, 120, 5, 0))
  run_steps(env, 1)
  assert_true(r.kx > 0, "the wave knocked the rocket (kx " .. r.kx .. ")")
  assert_true(r.x > 145, "the knocked rocket drifted away (x " .. r.x .. ")")
end
do
  -- firing a shockwave releases an attached rope
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ceiling(g)
  rig_rope_arrow(g)
  place_player(g, 100, 192)
  run_steps(env, 2)
  assert_true(p.rope ~= nil, "attached for the shockwave-release test")
  select_shockwave(env)
  fire_at(env, g, 0.25)
  assert_true(p.rope == nil, "the shockwave fire released the rope")
end
do
  -- waves bypass the arrow quiver but respect their own airborne cap
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 180)
  p.gr = false
  select_shockwave(env)
  for _ = 1, 3 do
    table.insert(g.ctx.ents.arrows, {
      x = 140, y = 200, vx = 2, vy = 0, active = true, stuck = false,
      bounced = 0, sdx = 2, sdy = 0, spin = 0, lt = 300,
      kind = "normal",
    })
  end
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.shockwaves == 1,
    "a wave fired despite a full arrow quiver")
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.shockwaves == 2, "a second wave went airborne")
  fire_at(env, g, 0.25)
  assert_true(#g.ctx.ents.shockwaves == 2, "the cap dropped the third wave")
end

print(("rope tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
