-- Level select tests (deterministic, headless; requires LuaJIT).
--
-- Covers the launch level select (Game:select_step /
-- src/render/levelselect.lua). The harness boots straight into play, so
-- these tests flip game.mode to "select" to exercise the screen:
--   1. the harness skips the launch screen and boots into play
--   2. the cursor starts on the booted level and wraps with up/down
--   3. locked levels refuse to start (no save, unlock-all off)
--   4. unlock-all (or a save entry) opens the gates; jump/aim/swap then
--      start the highlighted level: a fresh load of that map
--      (new world/ents, full-health player) and the sim resumes
--   5. m / start don't open the test menu in select mode
--
-- Usage (from the project root): luajit tests/levelselect_test.lua

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

local config = dofile("src/config.lua")

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

local function open_select(env)
  local g = env.TWANG_TEST.game
  g.mode = "select"
  step(env)
end

-- ==== 1. the harness boots into play ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  assert_true(g.mode == "play", "the harness boots into play, no select")
  assert_true(g.map_file == config.map_file,
    "the booted level is config.map_file")
  local boot_index
  for i, entry in ipairs(g.select_levels) do
    if entry.file == g.map_file then boot_index = i end
  end
  assert_true(boot_index ~= nil, "the booted level is in the select rows")
  assert_true(g.level_sel == boot_index,
    "the cursor starts on the booted level")
end

-- ==== 2. cursor movement with wraparound ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  g.mode = "select"
  step(env)
  local n = #g.select_levels
  assert_true(n == #config.levels, "no hidden levels: all rows show")
  local start = g.level_sel
  local function nudge(key)
    keys[key] = true
    step(env)
    keys[key] = nil
    step(env)  -- release step so the next press is a fresh edge
  end
  nudge("down")
  assert_true(g.level_sel == (start % n) + 1, "down moves the cursor")
  for _ = 1, n - 1 do nudge("down") end  -- to the last row and wrap around
  assert_true(g.level_sel == start, "down wraps from the last row to the first")
  nudge("up")
  local wrapped = (start == 1) and n or (start - 1)
  assert_true(g.level_sel == wrapped,
    "up wraps from the first row to the last")
  nudge("up")
  assert_true(g.level_sel == ((wrapped - 2) % n) + 1, "up moves the cursor")
end

-- ==== 3. locked levels refuse to start ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  assert_true(#g.select_levels >= 2, "there is a second row to test")
  g.mode = "select"
  step(env)
  -- the harness boots level1: the cursor starts on it, row 2 (row 1 is
  -- the farmhouse, still uncleared)
  assert_true(g.level_sel == 2, "the cursor starts on the booted level")
  assert_true(not g:level_unlocked(g.select_levels[2]),
    "with an empty save the second level is locked")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "select", "a locked level does not start")
  -- a cleared previous level opens the gate
  g.save["maps/farmhouse.json"] = { time = 50, grade = "silver" }
  assert_true(g:level_unlocked(g.select_levels[2]),
    "clearing the previous level unlocks the next")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "play", "the unlocked level starts")
end

-- ==== 4. unlock-all + starting a level ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  local old_ents = g.ctx.ents
  local n = #g.select_levels
  local start = g.level_sel
  g.unlocked_all = true  -- the test menu's debug toggle
  -- the player mustered some damage: the level select restarts clean
  g.ctx.player.hp = 4
  g.mode = "select"
  step(env)
  keys.down = true; step(env); keys.down = nil; step(env)  -- next row
  local target = (start % n) + 1
  assert_true(g.level_sel == target, "the next row is selected")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "play", "jump starts the selected level")
  assert_true(g.map_file == g.select_levels[target].file,
    "the chosen level's map is loaded")
  assert_true(g.ctx.ents ~= old_ents, "the level is a fresh load")
  assert_true(g.ctx.player.hp == 6, "the player restarts at full health")

  -- swap also confirms; the world simulates again afterwards
  g.mode = "select"
  step(env)
  env.love.keypressed("c")
  step(env)
  assert_true(g.mode == "play", "swap starts the selected level")
  local steps = g.step_count
  step(env)
  assert_true(g.step_count > steps, "the simulation runs after starting")

  -- aim (z) is a start too
  g.mode = "select"
  step(env)
  env.love.keypressed("z")
  step(env)
  assert_true(g.mode == "play", "aim starts the selected level")
end

-- ==== 4. the test menu is unreachable in select mode ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.mode = "select"
  step(env)
  env.love.keypressed("m")
  step(env)
  env.love.keypressed("tab")
  step(env)
  env.love.gamepadpressed(nil, "start")
  step(env)
  assert_true(not g.menu_open, "no test menu over the level select")
end

print(("level select tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
