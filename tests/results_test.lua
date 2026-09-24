-- Results/completion tests (deterministic, headless; requires LuaJIT).
--
-- Covers the level-clear flow (Game:complete_level / Game:complete_step /
-- Game.grade_for / src/save.lua):
--   1. a level without an exit never completes
--   2. touching an exit freezes the world on the results panel and
--      records the best time/grade in the save table
--   3. grades: <= gold -> gold, <= par -> silver, else bronze
--   4. Save.record keeps the strictly best time and the best grade
--      independently (a slow gold still shows its gold)
--   5. on the results panel: jump/aim continue to the next level (the
--      level select after the last one), swap replays the same level
--   6. deaths are counted through the die route
--
-- Usage (from the project root): luajit tests/results_test.lua

local Harness = dofile("tests/harness.lua")
local Save = dofile("src/save.lua")

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

-- Overlaps the player with a fresh exit entity (tests inject it; the
-- shipped maps place exits in Tiled).
local function touch_exit_with_player(env)
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  table.insert(g.ctx.ents.exits, { x = p.x, y = p.y })
end

-- ==== 1. no exit, no completion ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  assert_true(#g.ctx.ents.exits == 0, "the pinned level has no exit")
  for _ = 1, 10 do step(env) end
  assert_true(g.mode == "play", "the level keeps playing without an exit")
end

-- ==== 2. touching an exit completes and records ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  assert_true(g.deaths == 0 and g.play_steps == 0,
    "run state starts at zero")
  touch_exit_with_player(env)
  step(env)
  assert_true(g.mode == "complete", "touching the exit completes the level")
  local r = g.result
  assert_true(r ~= nil, "the run summary exists")
  assert_true(r.time > 0 and r.time <= 1,
    "the recorded time is the played clock (seconds)")
  assert_true(r.deaths == 0, "no deaths recorded on a clean run")
  assert_true(r.grade == "gold", "a near-instant run grades gold")
  local best = g.save[g.map_file]
  assert_true(best ~= nil and best.time ~= nil,
    "the finish is recorded in the save table")
  assert_true(best.grade == "gold", "the grade is recorded")
  -- the world is frozen: enemies/arrows no longer step
  local ents = g.ctx.ents
  step(env)
  step(env)
  assert_true(g.play_steps == 1,
    "the level clock stops once the level is complete")
  assert_true(#ents.e_arrows == 0, "no stray simulation behind the panel")
end

-- ==== 3. grade thresholds ====
do
  local Game = dofile("src/game.lua")
  local entry = { gold = 10, par = 20 }
  assert_true(Game.grade_for(entry, 5) == "gold", "under gold grades gold")
  assert_true(Game.grade_for(entry, 10) == "gold", "gold boundary is <= gold")
  assert_true(Game.grade_for(entry, 10.1) == "silver",
    "just over gold grades silver")
  assert_true(Game.grade_for(entry, 20) == "silver",
    "silver boundary is <= par")
  assert_true(Game.grade_for(entry, 20.5) == "bronze",
    "over par grades bronze")
  assert_true(Game.grade_for({}, 1) == "bronze",
    "an unthresholded level grades bronze")
end

-- ==== 4. Save.record keeps best time and best grade independently ====
do
  local data = {}
  Save.record(data, "maps/x.json", 100, "gold")
  Save.record(data, "maps/x.json", 50, "bronze")
  local best = data["maps/x.json"]
  assert_true(best.time == 50, "the faster run is kept")
  assert_true(best.grade == "gold", "the better grade is kept despite time")
  Save.record(data, "maps/x.json", 40, "silver")
  assert_true(data["maps/x.json"].time == 40, "a new best time replaces")
  assert_true(data["maps/x.json"].grade == "gold",
    "a lesser grade does not demote")
  assert_true(Save.cleared(data, "maps/x.json"),
    "a recorded run counts as cleared")
  assert_true(not Save.cleared(data, "maps/y.json"),
    "an unrecorded level is not cleared")
end

-- ==== 5. results-panel inputs ====
do
  -- jump continues to the next level
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g:start_level(config.levels[1])  -- the ladder's first level
  local p = g.ctx.player
  table.insert(g.ctx.ents.exits, { x = p.x, y = p.y })
  step(env)
  assert_true(g.mode == "complete", "the meadow completed")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "play", "jump leaves the results panel")
  assert_true(g.map_file == config.levels[2].file,
    "the next level in the list loads")
  assert_true(g.ctx.ents.exits ~= nil and #g.ctx.ents.exits >= 1,
    "the new level is a fresh load (with its own exit)")
  assert_true(g.play_steps == 0, "the new level's clock restarts at zero")
  step(env)
  assert_true(g.play_steps == 1, "the new level's clock runs again")

  -- completing the last visible level sends jump to the level select
  local p2 = g.ctx.player
  table.insert(g.ctx.ents.exits, { x = p2.x, y = p2.y })
  step(env)
  assert_true(g.mode == "complete", "the second level completed")
  -- make it the final run: point the game at the ladder's last level
  -- (debug rows sit outside the ladder)
  local last = nil
  for _, entry in ipairs(config.levels) do
    if not entry.hidden and not entry.debug then last = entry end
  end
  g:load_level(last.file)
  g.mode = "play"
  local p3 = g.ctx.player
  table.insert(g.ctx.ents.exits, { x = p3.x, y = p3.y })
  step(env)
  assert_true(g.mode == "complete" and g.result.last,
    "the final level's results know it is last")
  env.love.keypressed("x")
  step(env)
  assert_true(g.mode == "select", "after the last level: the level select")
end
do
  -- swap replays the same level fresh
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  touch_exit_with_player(env)
  step(env)
  assert_true(g.mode == "complete", "level 1 completed")
  env.love.keypressed("c")
  step(env)
  assert_true(g.mode == "play" and g.map_file == "maps/level1.json",
    "swap replays the same level")
  assert_true(g.play_steps == 0 and g.deaths == 0 and g.result == nil,
    "the replay resets the run state")
  step(env)
  assert_true(g.play_steps == 1, "the replay's clock runs again")
end

-- ==== 6. deaths are counted through the die route ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.die(g.ctx)
  assert_true(g.deaths == 1, "a death through ctx.die is counted")
  g.ctx.die(g.ctx)
  assert_true(g.deaths == 2, "deaths accumulate")
  touch_exit_with_player(env)
  step(env)
  assert_true(g.mode == "complete" and g.result.deaths == 2,
    "the results panel shows the death count")
  local best = g.save[g.map_file]
  assert_true(best.time ~= nil,
    "the run is recorded (deaths do not block recording)")
end

print(("results tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
