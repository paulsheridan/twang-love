-- Level select tests (deterministic, headless; requires LuaJIT).
--
-- Covers the launch level select (Game:select_step /
-- src/render/levelselect.lua). The harness boots straight into play, so
-- these tests flip game.mode to "select" to exercise the screen:
--   1. the harness skips the launch screen and boots into play; hidden
--      workshop levels are not select rows and the cursor falls to row 1
--   2. the cursor wraps with up/down over the menu's rows (one row today)
--   3. locked levels refuse to start (no save, unlock-all off); the gate
--      opens once the previous level is cleared
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

-- The shipped menu has a single row (the room grid), so gating cannot be
-- observed on real content. Tests that exercise the gate append a
-- synthetic second row to the game's select list: the machinery is
-- generic (it gates row N on row N-1's save entry), so this keeps it
-- covered even while there is only one shipping level.
local function add_second_row(g)
  g.select_levels[2] = { file = "maps/legacy/meadow.json", name = "fake" }
end

-- ==== 1. the harness boots into play ====
do
  local env = Harness.boot(config.map_file)
  local g = env.TWANG_TEST.game
  assert_true(g.mode == "play", "the harness boots into play, no select")
  assert_true(g.map_file == config.map_file,
    "the booted level is config.map_file")
  -- the booted level is the shipped row: the cursor starts on it
  assert_true(#g.select_levels == 1, "the menu lists the one shipped level")
  assert_true(g.select_levels[1].file == config.map_file,
    "row 1 is the shipped level")
  assert_true(g.level_sel == 1, "the cursor starts on the booted level")
  assert_true(not g.select_levels[1].debug,
    "the shipped row is a real level, not a debug row")
end

-- ==== 2. cursor movement with wraparound ====
do
  local env = Harness.boot(config.map_file)
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  g.mode = "select"
  step(env)
  local n = #g.select_levels
  assert_true(n == 1, "the select shows the one shipped level")
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
  nudge("up")
  assert_true(g.level_sel == ((start - 2) % n) + 1, "up moves the cursor")
  -- the only row is always unlocked with an empty save
  assert_true(g:level_unlocked(g.select_levels[1]),
    "the shipped row opens without any progression")
end

-- ==== 3. locked levels refuse to start ====
do
  local env = Harness.boot(config.map_file)
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  add_second_row(g)
  g.mode = "select"
  g.level_sel = 1
  step(env)
  -- nudge to row 2
  keys.down = true; step(env); keys.down = nil; step(env)
  assert_true(not g:level_unlocked(g.select_levels[2]),
    "with an empty save the second level is locked")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "select", "a locked level does not start")
  -- a cleared previous level opens the gate
  g.save[g.select_levels[1].file] = { time = 50, grade = "silver" }
  assert_true(g:level_unlocked(g.select_levels[2]),
    "clearing the previous level unlocks the next")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "play", "the unlocked level starts")
  assert_true(g.map_file == g.select_levels[2].file,
    "the chosen level's map is loaded")
end

-- ==== 4. unlock-all + starting a level ====
do
  local env = Harness.boot(config.map_file)
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  local old_ents = g.ctx.ents
  g.unlocked_all = true  -- the test menu's debug toggle
  -- the player mustered some damage: the level select restarts clean
  g.ctx.player.hp = 4
  g.mode = "select"
  step(env)
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "play", "jump starts the selected level")
  assert_true(g.map_file == g.select_levels[1].file,
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
  local env = Harness.boot(config.map_file)
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
