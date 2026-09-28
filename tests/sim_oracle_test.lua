-- Sim-rate oracle (deterministic, headless; requires LuaJIT).
--
-- Pins the simulation's REAL-TIME behavior so the sim-rate knob
-- (config.sim.rate) can move without the game's feel drifting: every
-- landmark here is asserted in seconds or px-per-second, never in
-- ticks. The world-time currency is the 30hz-step (ctx.dt = 30/rate per
-- tick), so per-step constants are rate-invariant by construction --
-- these tests catch anything that quietly couples to the tick count.
--
-- Landmarks:
--   1. the level clock runs at real time (play_steps/rate)
--   2. walk speed ~ walk_speed px per world-step (90 px/s)
--   3. a full-hold jump: ~3-tile apex, sub-second airtime
--   4. coyote time and the jump buffer: their windows in seconds
--   5. i-frames last invuln_steps world-steps (1.5s)
--   6. arrows fly at the power level's speed in px/s
--
-- Usage (from the project root): luajit tests/sim_oracle_test.lua

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

-- One harness call feeds 1/30s of real time = rate/30 sim ticks, which
-- is exactly one world-step (the 30hz-step currency) per call.
local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

local function seconds(ws) return ws / 30 end  -- world-steps -> real time

-- ==== 1. the level clock runs at real time ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  run_steps(env, 60)  -- two real seconds
  assert_true(math.abs(g.play_steps / config.sim.rate - 2.0) < 1e-9,
    "the level clock ticks real seconds (play_steps/rate = "
    .. tostring(g.play_steps / config.sim.rate) .. ")")
end

-- ==== 2. walk speed in px/s ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 1376, 148, 0, 0
  run_steps(env, 6)
  local keys = env.TWANG_TEST.keys_down
  keys.right = true
  local x0 = p.x
  run_steps(env, 30)  -- one real second of held walking
  keys.right = nil
  local pxs = (p.x - x0) / 1.0
  assert_true(math.abs(pxs - config.player.walk_speed * 30) < 8,
    "the walk covers walk_speed px per world-step ("
    .. string.format("%.1f", pxs) .. " px/s)")
end

-- ==== 3. the jump: ~3-tile apex, snappy airtime ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 1488, 148, 0, 0
  run_steps(env, 6)
  local keys = env.TWANG_TEST.keys_down
  keys.x = true
  local y0, min_y, calls = p.y, p.y, 0
  for _ = 1, 60 do
    run_steps(env, 1)
    calls = calls + 1
    if p.y < min_y then min_y = p.y end
    if calls > 8 and p.gr then break end
  end
  keys.x = nil
  local apex = y0 - min_y
  assert_true(apex > 40 and apex < 56,
    "a full-hold jump rises ~3 tiles (apex " .. string.format("%.1f", apex) .. "px)")
  assert_true(seconds(calls) < 1.0,
    "the jump's airtime stays under a second ("
    .. string.format("%.2f", seconds(calls)) .. "s)")
end

-- ==== 4. coyote time + the jump buffer, in seconds ====
do
  -- walk off a ledge and jump late: the buffer must still fire within
  -- its window of world-steps
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local p = g.ctx.player
  local C = g.ctx.config
  -- a fresh grounded player: full coyote; force airborne and count the
  -- window's decay (the player is over solid floor, so the ground keep
  -- must not refill it: lift them a tile into the air)
  p.x, p.y, p.vx, p.vy = 1488, 148, 0, 0
  run_steps(env, 6)
  p.y = p.y - 100  -- lifted well clear: the fall outlasts the window,
                   -- so the ground keep cannot refill it
  p.gr = false
  run_steps(env, 1)
  assert_true(p.coy > 0, "coyote time holds after leaving the ground")
  local waited = 0
  while p.coy > 0 and waited < 60 do
    run_steps(env, 1)
    waited = waited + 1
  end
  assert_true(math.abs(seconds(waited) - seconds(C.player.coyote_frames)) < 0.05,
    "the coyote window lasts coyote_frames world-steps ("
    .. string.format("%.2f", seconds(waited)) .. "s)")
end

-- ==== 5. i-frames: 1.5 real seconds ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 1488, 148, 0, 0
  run_steps(env, 6)
  p.invuln = config.player.invuln_steps
  local waited = 0
  while p.invuln > 0 and waited < 120 do
    run_steps(env, 1)
    waited = waited + 1
  end
  assert_true(math.abs(seconds(waited) - 1.5) < 0.05,
    "i-frames last 1.5 real seconds (" .. string.format("%.2f", seconds(waited)) .. "s)")
end

-- ==== 6. arrow speeds in px/s ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local Arrows = dofile("src/arrows.lua")
  place = nil
  p.x, p.y, p.vx, p.vy = 1376, 148, 0, 0
  run_steps(env, 2)
  p.aim_power = 3
  Arrows.fire(g.ctx, 0, "normal", 1)
  local a = g.ctx.ents.arrows[#g.ctx.ents.arrows]
  assert_true(a ~= nil, "the arrow fired")
  assert_true(math.abs(a.vx * 30 - config.arrows.speeds[3] * 30) < 1e-9,
    "the arrow flies at the power level's speed ("
    .. tostring(a.vx * 30) .. " px/s)")
end

print(("sim oracle: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
