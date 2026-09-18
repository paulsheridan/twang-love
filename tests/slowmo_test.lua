-- Slow-motion tests (deterministic, headless; requires LuaJIT).
--
-- Covers the dt-parametric slow motion:
--   1. ctx.dt is 1 normally, 1/aiming.slow_motion_steps while aiming
--   2. while aiming the world advances a little EVERY step (steady
--      framerate slow motion): a flying arrow creeps forward each step
--      at ~1/N of its per-step speed instead of only moving every Nth
--   3. over slow_motion_steps aim steps the arrow flies one full step's
--      worth of world time
--   4. releasing aim resumes full speed (a full step per step again)
--
-- Usage (from the project root): luajit tests/slowmo_test.lua

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

local function place_player(g, x, y)
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- Fires an arrow by holding aim one step, forcing the angle, then
-- releasing (fires on the release step, which itself runs at dt=1).
local function fire_at(env, g, angle)
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 1)
  g.ctx.player.aim_angle = angle
  kd.z = false
  run_steps(env, 1)
end

local env = Harness.boot()
local g = env.TWANG_TEST.game
local p = g.ctx.player
local cfg = g.ctx.config

assert_true(g.ctx.dt == 1, "world time advances at dt=1 outside aim mode")

-- ==== fire a flat shot into clear sky ====
place_player(g, 80, 212)  -- standing on the spawn-area floor; row 13 above
                          -- it is open sky, so the shot flies unobstructed
run_steps(env, 2)
fire_at(env, g, 0)
local a = g.ctx.ents.arrows[1]
assert_true(a and a.active, "the arrow fired into clear sky")
local spd = cfg.arrows.speeds[p.aim_power]
local x0 = a.x
assert_true(math.abs(a.x - (p.x + p.w/2 + spd)) < 0.01,
  "the arrow flew one full step on the release step (x " .. a.x .. ")")

-- ==== 1. dt while aiming ====
local kd = env.TWANG_TEST.keys_down
kd.z = true
run_steps(env, 1)
assert_true(g.ctx.dt == 1 / cfg.aiming.slow_motion_steps,
  "aiming divides world time by aiming.slow_motion_steps (dt "
    .. tostring(g.ctx.dt) .. ")")

-- ==== 2. the world creeps forward every aim step ====
local x1 = a.x
run_steps(env, 1)
local x2 = a.x
assert_true(x2 > x1 and x2 - x1 < spd / 2,
  "the arrow advances a fraction of a step per aim step (dx "
    .. (x2 - x1) .. ")")

-- ==== 3. slow_motion_steps aim steps equal one full world step ====
local before = a.x
run_steps(env, cfg.aiming.slow_motion_steps - 1)  -- N aim steps in total
local after = a.x
assert_true(math.abs((after - x1) - spd) < 0.01,
  "N aim steps advance the arrow one full step's flight ("
    .. (after - x1) .. ", expected " .. spd .. ")")

-- ==== 4. releasing aim resumes full speed ====
kd.z = false
run_steps(env, 1)
assert_true(g.ctx.dt == 1, "releasing aim restores dt=1")
assert_true(math.abs(a.x - after - spd) < 0.01,
  "the arrow flies a full step per step again (dx " .. (a.x - after) .. ")")

print(("slowmo tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
