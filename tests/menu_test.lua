-- Test menu tests (deterministic, headless; requires LuaJIT).
--
-- Covers the panel (m / tab / start) and its three toggles
-- (see Game:menu_step / src/render/menu.lua):
--   1. opening and closing the panel (m, start; z / x close)
--   2. up/down selection with wraparound
--   3. the swap key toggles the highlighted row: puzzle pieces hidden,
--      invincibility, enemies off
--   4. the old enemies shortcuts (keyboard e, pad Y) are unmapped
--
-- Usage (from the project root): luajit tests/menu_test.lua

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

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- ==== 1. open and close the panel ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  assert_true(not g.menu_open, "the panel starts closed")
  env.love.keypressed("m")
  step(env)
  assert_true(g.menu_open, "m opens the test menu")
  env.love.keypressed("x")  -- jump closes (also z/aim)
  step(env)
  assert_true(not g.menu_open, "x closes the test menu")
  -- the gamepad's start button opens it too (callbacks take pad, button)
  env.love.gamepadpressed(nil, "start")
  step(env)
  assert_true(g.menu_open, "start opens the test menu")
  env.love.gamepadpressed(nil, "back")  -- back quits the game entirely
  step(env)
end

-- ==== 2. up/down selection with wraparound ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  env.love.keypressed("m")
  step(env)
  assert_true(g.menu_sel == 1, "selection starts on the first row")
  local function nudge(key, times)
    for _ = 1, (times or 1) do
      keys[key] = true
      step(env)
      keys[key] = nil
      step(env)  -- release step so the next press is a fresh edge
    end
  end
  nudge("down")
  assert_true(g.menu_sel == 2, "down moves the selection")
  nudge("down", 2)
  assert_true(g.menu_sel == 1, "down wraps from the last row to the first")
  nudge("up")
  assert_true(g.menu_sel == 3, "up wraps from the first row to the last")
  nudge("up")
  assert_true(g.menu_sel == 2, "up moves the selection")
end

-- ==== 3. each row toggles its feature ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local keys = env.TWANG_TEST.keys_down
  local ents = g.ctx.ents
  env.love.keypressed("m")
  step(env)

  -- row 1 (default selection): puzzle pieces hidden
  env.love.keypressed("c")
  step(env)
  assert_true(g.settings.no_puzzle, "row 1 hides the puzzle pieces")
  local door = ents.doors[1]
  assert_true(door.open, "hidden doors stand open")
  assert_true(ents.keys[1].taken, "hidden keys are taken")
  env.love.keypressed("c")
  step(env)
  assert_true(not g.settings.no_puzzle and not door.open,
    "row 1 restores the puzzle")

  -- row 2: invincibility actually shields the player
  keys.down = true; step(env); keys.down = nil; step(env)
  assert_true(g.menu_sel == 2, "the second row is selected")
  env.love.keypressed("c")
  step(env)
  assert_true(g.settings.invincible, "row 2 turns on invincibility")
  place_player(g, 720, 148)
  local hurt = g.ctx.hurt
  assert_true(hurt(g.ctx, 8, 0) == false and g.ctx.player.hp == 6,
    "an invincible player takes no damage from hurt()")
  env.love.keypressed("c")
  step(env)
  assert_true(not g.settings.invincible, "row 2 turns invincibility off")

  -- row 3: enemies on/off (the old pad-Y behaviour, moved here)
  keys.down = true; step(env); keys.down = nil; step(env)
  assert_true(g.menu_sel == 3, "the third row is selected")
  env.love.keypressed("c")
  step(env)
  assert_true(not g.ctx.config.enemies.enabled,
    "row 3 disables the enemies")
  env.love.keypressed("c")
  step(env)
  assert_true(g.ctx.config.enemies.enabled, "row 3 re-enables the enemies")

  env.love.keypressed("z")  -- aim closes as well
  step(env)
  assert_true(not g.menu_open, "z closes the test menu")
end

-- ==== 4. the old enemies shortcuts are unmapped ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  env.love.keypressed("e")
  step(env)
  assert_true(g.ctx.config.enemies.enabled,
    "the keyboard e key no longer toggles the enemies")
  env.love.gamepadpressed(nil, "y")
  step(env)
  assert_true(g.ctx.config.enemies.enabled,
    "the pad Y button no longer toggles the enemies")
  assert_true(not g.menu_open,
    "neither e nor Y disturbs the test menu")
end

print(("menu tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
