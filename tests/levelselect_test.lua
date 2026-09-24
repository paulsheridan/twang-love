-- Level select tests (deterministic, headless; requires LuaJIT).
--
-- Covers the launch level select (Game:select_step /
-- src/render/levelselect.lua). The harness boots straight into play, so
-- these tests flip game.mode to "select" to exercise the screen:
--   1. the harness skips the launch screen and boots into play; hidden
--      workshop levels are not select rows and the cursor falls to row 1
--   2. the cursor wraps with up/down over the v1 ladder's rows
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
  -- level1 is a hidden workshop level: not a select row; the cursor
  -- falls to the first row (the intro level of the v1 ladder)
  local boot_in_rows = false
  for _, entry in ipairs(g.select_levels) do
    if entry.file == g.map_file then boot_in_rows = true end
  end
  assert_true(not boot_in_rows, "the booted workshop level is hidden")
  assert_true(g.level_sel == 1, "the cursor falls to the first row")
  assert_true(g.select_levels[1].file == "maps/meadow.json",
    "row 1 is the meadow (the ladder's intro)")
end

-- ==== 2. cursor movement with wraparound ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  g.mode = "select"
  step(env)
  local n = #g.select_levels
  assert_true(n == 8, "the v1 ladder shows eight rows")
  for _, entry in ipairs(config.levels) do
    if entry.hidden then
      local shown = false
      for _, visible in ipairs(g.select_levels) do
        if visible == entry then shown = true end
      end
      assert_true(not shown, "hidden level " .. entry.file .. " is not shown")
    end
  end
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
  -- the cursor is on row 1 (the meadow, unlocked); nudge to row 2
  keys.down = true; step(env); keys.down = nil; step(env)
  assert_true(not g:level_unlocked(g.select_levels[2]),
    "with an empty save the second level is locked")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "select", "a locked level does not start")
  -- a cleared previous level opens the gate
  g.save["maps/meadow.json"] = { time = 50, grade = "silver" }
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

-- ==== 5. the test menu is unreachable in select mode ====
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
