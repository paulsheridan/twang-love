-- Wall-run tests (deterministic, headless; requires LuaJIT).
--
-- Covers the wall-run over lines of runnable tiles (the checkered boxes;
-- level1's row sits at ground-layer row 27, cols 6-15: x 96..256,
-- y 432..448, two tiles above the floor at row 30):
--   1. trigger: holding jump + pushing toward the line with the body's
--      centre inside one of its end tiles engages the run
--   2. the ride settles onto the band's centre line; no gravity mid-run
--   3. holding the direction carries the player the line's full length;
--      reaching the far end with jump held fires the end-jump
--   4. reaching the far end without jump keeps the momentum and falls
--   5. releasing the direction mid-run stops and drops straight down
--   6. the middle tiles of a line never engage the run (ends only)
--   7. no trigger without the jump button held
--   8. the line scan (runnable_line) spans the row; empty squares and
--      other rows answer nil
--   9. the band is pass-through: a body dropped on the line falls through
--
-- Usage (from the project root): luajit tests/wallrun_test.lua

local Harness = dofile("tests/harness.lua")
local config = require("src.config")

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

-- Runs steps until the wall-run ends (or the cap trips); returns the
-- number of steps taken.
local function run_until_done(env, cap)
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local steps = 0
  while p.wallrun and steps < cap do
    run_steps(env, 1)
    steps = steps + 1
  end
  return steps
end

-- level1's placed line: ground row 27, columns 6..15 (10 tiles).
local LINE_ROW = 27
local LINE_C0, LINE_C1 = 6, 15
local PIN_Y = LINE_ROW * 16 + (16 - 12) / 2

-- ==== 1. trigger from the line's left end tile ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  -- centre inside the leftmost tile (col 6: x 96..112)
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 1)
  assert_true(p.wallrun ~= nil, "the run engages from the line's left end tile")
  assert_true(p.wallrun.dir == 1, "the run direction follows the pushed stick")
  assert_true(p.wallrun.c_end == LINE_C1,
    "the run targets the line's far end (got " .. tostring(p.wallrun
    and p.wallrun.c_end) .. ")")
  assert_true(p.vx == config.wallrun.speed, "the run moves at its own speed")
end

-- ==== 2. the ride settles onto the band's centre; no gravity mid-run ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, config.wallrun.settle_steps + 2)
  assert_true(p.wallrun ~= nil, "the run holds while the direction is held")
  assert_true(math.abs(p.y - PIN_Y) < 0.01,
    "the ride settles onto the band's centre (y " .. p.y .. ")")
  assert_true(p.vy == 0, "no gravity while wall-running")
end

-- ==== 3. full-length run; the held jump fires the end-jump ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 1)
  local steps = run_until_done(env, 90)
  assert_true(steps > 10 and steps < 60,
    "the run lasts about the line's length at run speed (steps " .. steps .. ")")
  assert_true(p.wallrun == nil, "the run ends at the line's far end")
  assert_true(p.x + p.w >= LINE_C1 * 16,
    "the handover happens inside the last tile (lead edge " .. (p.x + p.w) .. ")")
  assert_true(p.vy == config.player.jump_velocity,
    "the held jump launches at the wall's end (vy " .. p.vy .. ")")
  assert_true(p.vx == config.wallrun.speed,
    "the end-jump keeps the run's forward momentum (vx " .. p.vx .. ")")
  -- the held jump extends like a normal jump (j_frames handed over)
  assert_true(p.j_frames == config.player.jump_hold_frames,
    "the end-jump is holdable (j_frames " .. p.j_frames .. ")")
end

-- ==== 4. the far end without jump: momentum kept, fall begins ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 3)
  assert_true(p.wallrun ~= nil, "the run engaged for the no-jump exit")
  env.TWANG_TEST.keys_down.x = false
  run_steps(env, 1)
  assert_true(p.wallrun ~= nil,
    "the run continues on the direction alone (jump is only an exit bonus)")
  local steps = run_until_done(env, 90)
  assert_true(p.wallrun == nil, "the run still ends at the line's far end")
  assert_true(p.vy == 0, "the momentum exit starts from rest (vy " .. p.vy .. ")")
  assert_true(p.vx == config.wallrun.speed,
    "the momentum is maintained (vx " .. p.vx .. ")")
  run_steps(env, 3)
  assert_true(p.vy > 0, "gravity resumes: the player begins to fall")
end

-- ==== 5. releasing the direction mid-run: stop and drop straight down ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 12)  -- partway along the band
  assert_true(p.wallrun ~= nil, "the run is underway for the release test")
  env.TWANG_TEST.keys_down.right = false
  run_steps(env, 1)
  assert_true(p.wallrun == nil, "the run ends when the direction is released")
  assert_true(p.vx == 0, "the forward motion stops (vx " .. p.vx .. ")")
  local x = p.x
  run_steps(env, 3)
  assert_true(p.x == x, "the player drops straight down (x frozen)")
  assert_true(p.vy > 0, "the player falls from the band")
end

-- ==== 6. the middle tiles of a line never engage the run ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  -- centre inside col 10 (x 160..176), a middle tile of the line
  place_player(g, 164, 436)
  env.TWANG_TEST.keys_down.right = true
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 3)
  assert_true(p.wallrun == nil, "a middle tile does not engage the run")
  env.TWANG_TEST.keys_down.left = true
  env.TWANG_TEST.keys_down.right = false
  run_steps(env, 3)
  assert_true(p.wallrun == nil,
    "pushing back along a line from a middle tile does not engage either")
end

-- ==== 7. no trigger without the jump button held ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 100, 436)
  env.TWANG_TEST.keys_down.right = true
  run_steps(env, 3)
  assert_true(p.wallrun == nil,
    "the run needs the jump button held at the trigger")
end

-- ==== 8. the line scan ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local w = g.ctx.world
  local c0, c1 = w:runnable_line(8, LINE_ROW)
  assert_true(c0 == LINE_C0 and c1 == LINE_C1,
    "runnable_line spans the placed row (got " .. c0 .. ".." .. c1 .. ")")
  local c0b, c1b = w:runnable_line(LINE_C0, LINE_ROW)
  local c0c, c1c = w:runnable_line(LINE_C1, LINE_ROW)
  assert_true(c0b == LINE_C0 and c1b == LINE_C1 and c0c == LINE_C0
    and c1c == LINE_C1, "the scan is the same from any tile of the line")
  assert_true(w:runnable_line(5, LINE_ROW) == nil,
    "the empty square beside the line is not runnable")
  assert_true(w:runnable_line(8, LINE_ROW + 1) == nil,
    "a plain-air row is not runnable")
  assert_true(w:runnable(0) == false, "tile 0 (outside the map) is inert")
end

-- ==== 9. the band is pass-through: bodies fall through the line ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  -- standing height on the line's top (row 26 band), no input held
  place_player(g, 100, 420)
  run_steps(env, 40)
  assert_true(not p.wallrun, "a falling body never wall-runs without input")
  assert_true(p.gr and math.abs(p.y + p.h - 480) < 2,
    "the player fell through the line and landed on the floor below (y "
    .. (p.y + p.h) .. ")")
end

print("wallrun tests: " .. PASS .. " passed, " .. FAIL .. " failed")
if FAIL > 0 then os.exit(1) end
