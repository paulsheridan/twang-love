-- Laser rifleman behaviour tests (deterministic, headless; requires
-- LuaJIT).
--
-- A synthetic laser is inserted into the level at a stable perch (the
-- long lower floor, px 352/body top y 368 -- committed terrain, so the
-- test geometry doesn't chase map edits of the level's own laser
-- placements).
--
-- The laser shares the archer's see -> aim -> shoot -> investigate
-- brain, swapping the ballistic volley for a wall-to-wall beam:
--   1. spotting the player enters the aim state (aim fields set)
--   2. the blink-aim telegraph fires a beam after laser_sight_steps
--   3. the beam marches until it hits a wall (not the world's edge)
--   4. a beam hit costs a full heart, once per shot (i-frames hold the
--      lingering beam off)
--   5. the beam fires at the last known spot and misses a player who
--      fled mid-aim (then covers, then investigates)
--   6. terrain between the laser and the player blocks the sight
--   7. the rapid cadence re-aims and fires again while the player stays
--      visible, on the laser's slower randomized window
--   8. the test menu's enemies toggle disarms a firing laser
--
-- Usage (from the project root): luajit tests/laser_test.lua

local Harness = dofile("tests/harness.lua")

local config = dofile("src/config.lua")

local PASS, FAIL = 0, 0
local function assert_true(cond, msg)
  if cond then
    PASS = PASS + 1
  else
    FAIL = FAIL + 1
    print("FAIL: " .. msg)
  end
end

local function fresh_game()
  local keys, quit = {}, { false }
  local env = Harness.new_env(keys, quit)
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  env.love.load()
  return env
end

local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- Builds a laser rifleman with the level spawn's full field set.
local function make_laser(game, x, y)
  local cfg = game.ctx.config.enemies
  local e = {
    x = x, y = y, home_x = x,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, type = "laser",
    shoot_cd = 0, spr = 138, rot = nil,
    state = "patrol", aim_t = 0, last_known = nil,
  }
  table.insert(game.ctx.ents.enemies, e)
  return e
end

-- Test perches on stable, committed terrain:
--   the long lower floor at (352,368), guarding the wide corridor
--   the small mid platform at (512,304): a player standing directly
--   below it on the lower floor is hidden behind the platform tiles
local FLOOR_X, FLOOR_Y = 352, 368
local SPOT_X, SPOT_Y = 450, 372  -- ~100px in front on the same floor

-- Pins the laser at its perch and clears its cooldown (setup only: the
-- per-step hold below must never touch the cooldown fire_beam sets).
local function pin_laser(g, e, x, y)
  e.x, e.y, e.vx, e.vy = x, y, 0, 0
  e.shoot_cd = 0
end

-- Per-step position hold: keeps the laser on its perch without touching
-- its timers.
local function hold_laser(g, e, x, y)
  e.x, e.y, e.vx, e.vy = x, y, 0, 0
end

-- Warm-up: pins both bodies a few steps so the sight picture is stable.
local function settle(env, g, e, x, y, n, px, py)
  for _ = 1, n or 8 do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
  end
end

-- Runs steps until the telegraph fires (then one more, so the beam's
-- first live tick -- damage check included -- has processed). Pins both
-- bodies every step. Returns true once a beam is live.
local function fire_first_beam(env, g, e, x, y, px, py)
  for _ = 1, math.ceil(config.enemies.laser_sight_steps) + 4 do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
    if e.beam then
      env.love.update(1/30)
      env.love.draw()
      hold_laser(g, e, x, y)
      place_player(g, px or SPOT_X, py or SPOT_Y)
      return true
    end
  end
  return false
end

-- ==== 1. spotting enters the aim state ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 2)
  assert_true(e.state == "aim", "the laser aims once the player is spotted")
  assert_true(e.aim_t ~= nil and e.aim_t > 0
    and e.aim_t <= config.enemies.laser_sight_steps,
    "the aim has a blink-telegraph timer")
  assert_true(e.aim_dx ~= nil and e.aim_dy ~= nil,
    "the aim solves a fire direction")
  assert_true(e.last_known ~= nil, "the aim tracks the player's position")
  assert_true(e.aim_dx > 0, "the laser faces its aim")
  assert_true(e.beam == nil, "nothing fires while the sight still blinks")
end

-- ==== 2. the telegraph fires the beam ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 3)
  assert_true(e.state == "aim", "the laser is mid-telegraph")
  assert_true(fire_first_beam(env, g, e, FLOOR_X, FLOOR_Y),
    "the blink-aim ends in a fired beam")
  assert_true(e.beam.t > 0 and e.beam.t <= config.enemies.laser_beam_steps,
    "the beam is live for its burn duration")
  assert_true(e.beam.dx > 0, "the beam flies along the aim (at the player)")
  assert_true(e.state == "wait", "the laser waits for its cadence after firing")
  assert_true(e.shoot_cd > 0, "firing starts the shoot cooldown")
end

-- ==== 3. the beam marches until it hits a wall ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  assert_true(fire_first_beam(env, g, e, FLOOR_X, FLOOR_Y), "the laser fired")
  local b = e.beam
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local hx, hy = ex + b.dx*b.len, ey + b.dy*b.len
  -- the beam runs along the corridor until terrain catches it (the aim
  -- dips slightly, so the floor takes it a few hundred px out); the
  -- march only caps at the world bounds when there is no wall at all
  local bound = (g.ctx.world.px_w - ex) / b.dx
  assert_true(b.len > 250 and b.len < bound,
    "the beam reaches the far wall (len " .. string.format("%.1f", b.len)
    .. ", bound " .. string.format("%.1f", bound) .. ")")
  local world = g.ctx.world
  local solid_past = world:solid_for_arrow(hx + b.dx*3, hy + b.dy*3)
    or world:in_slope_solid(hx + b.dx*3, hy + b.dy*3)
  assert_true(solid_past, "the beam stops at a wall (solid just past its tip)")
end

-- ==== 4. a beam hit costs a full heart, once per shot ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  assert_true(fire_first_beam(env, g, e, FLOOR_X, FLOOR_Y),
    "the laser fired at the player in its path")
  local p = g.ctx.player
  local max_hp = config.player.hearts * 2
  assert_true(p.hp == max_hp - config.enemies.laser_half_hearts,
    "the beam costs a full heart (hp " .. p.hp .. ")")
  assert_true(p.invuln > 0, "the hit grants i-frames")
  assert_true(#g.ctx.ents.particles >= config.particles.blood_count,
    "the hit sprays blood")
  -- the beam lingers: i-frames must hold it to a single hit
  for _ = 1, math.ceil(config.enemies.laser_beam_steps) do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, FLOOR_X, FLOOR_Y)
    place_player(g, SPOT_X, SPOT_Y)
  end
  assert_true(p.hp == max_hp - config.enemies.laser_half_hearts,
    "the lingering beam cannot hit again through i-frames")
  assert_true(e.beam == nil, "the beam shuts off after its burn duration")
end

-- ==== 5. the beam fires at the last known spot, misses a fleeing player ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 3)
  -- vanish the player mid-aim (far away, out of sight): the beam still
  -- fires at the last tracked spot
  local fled = false
  local fired = false
  for _ = 1, math.ceil(config.enemies.laser_sight_steps) + 4 do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, FLOOR_X, FLOOR_Y)
    if e.state == "aim" and e.aim_t and e.aim_t <= 2 then
      fled = true
      place_player(g, 768, 208)  -- fled to the spawn
    else
      place_player(g, SPOT_X, SPOT_Y)
    end
    if e.beam then fired = true break end
  end
  assert_true(fled, "the player fled mid-telegraph")
  assert_true(fired, "the laser fires anyway when the player is lost")
  assert_true(e.state == "suppress",
    "losing the player mid-aim opens cover fire")
  local p = g.ctx.player
  assert_true(p.hp == config.player.hearts * 2,
    "the beam misses the player who fled (hp " .. p.hp .. ")")
  -- the beam must fire along the last known spot (not chase the player
  -- to the spawn): the segment must pass through it
  local b = e.beam
  local ex, ey = e.x + e.w/2, e.y + e.h/2
  local known = e.last_known
  local kdx, kdy = known.x - ex, known.y - ey
  local t = kdx * b.dx + kdy * b.dy  -- distance along the beam
  local px, py = ex + b.dx * t, ey + b.dy * t
  assert_true(t > 0 and t <= b.len, "the last known spot lies on the beam")
  assert_true(math.abs(px - known.x) < 8 and math.abs(py - known.y) < 8,
    "the beam passes through the last known player position")
end

-- ==== 6. terrain blocks the laser's sight ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_laser(g, 512, 304)
  -- the small platform (px 496..544, top y 320) hides a player standing
  -- directly below it on the lower floor: in detect range, no sight
  e.facing = 1
  place_player(g, 520, 372)
  run_steps(env, 60)
  assert_true(e.state ~= "aim", "the laser must not aim through terrain")
  assert_true(e.beam == nil, "no beam without line of sight")
end

-- ==== 7. the rapid cadence repeats while the player stays visible ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true  -- keep the pinned player alive all loop
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  local shots, waits = 0, {}
  local had_beam, last_state = false, e.state
  for _ = 1, 400 do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, FLOOR_X, FLOOR_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.beam and not had_beam then shots = shots + 1 end
    had_beam = e.beam ~= nil
    if e.state == "wait" and last_state ~= "wait" then
      waits[#waits + 1] = e.wait_t
    end
    last_state = e.state
  end
  assert_true(shots >= 2,
    "the laser keeps firing on its cadence (" .. shots .. " shots)")
  assert_true(#waits >= 1, "each shot is followed by a recharge wait")
  for _, wt in ipairs(waits) do
    assert_true(wt >= config.enemies.laser_rapid_min
      and wt <= config.enemies.laser_rapid_min + config.enemies.laser_rapid_extra,
      "each wait is within the laser's randomized window (" .. wt .. ")")
  end
end

-- ==== 8. the enemies toggle disarms a firing laser ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true
  local e = make_laser(g, FLOOR_X, FLOOR_Y)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  assert_true(fire_first_beam(env, g, e, FLOOR_X, FLOOR_Y),
    "the laser aimed and fired before the toggle")

  g:toggle_enemies()
  assert_true(not g.ctx.config.enemies.enabled, "the toggle turns the enemies off")
  assert_true(e.beam == nil and e.state == "patrol"
    and e.aim_dx == nil and e.aim_dy == nil,
    "a mid-shot laser drops back to patrol, beam off")
  local frozen_x = e.x
  for _ = 1, 30 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(e.x == frozen_x and e.beam == nil,
    "disabled lasers stay frozen and fire nothing")

  g:toggle_enemies()
  assert_true(g.ctx.config.enemies.enabled, "the toggle turns the enemies back on")
  e.shoot_cd = 0  -- the frozen cooldown would outlast this check
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    hold_laser(g, e, FLOOR_X, FLOOR_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.state == "aim" then break end
  end
  assert_true(e.state == "aim", "lasers resume hunting after re-enabling")
end

print(("laser tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
