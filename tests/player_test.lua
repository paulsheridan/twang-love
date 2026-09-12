-- Player health tests (deterministic, headless; requires LuaJIT).
--
-- Covers the hearts system (health in half-hearts, half a heart lost
-- per hit):
--   1. a melee touch costs half a heart and grants i-frames: further
--      contact is shielded until the invulnerability lapses
--   2. an enemy arrow hit costs half a heart
--   3. the last half-heart lost is fatal: death, respawn with a full
--      refill, arrows cleared
--   4. falling off the world is an instant death and refills health
--
-- Usage (from the project root): luajit tests/player_test.lua

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

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

local function max_hp() return 6 end  -- 3 hearts * 2 half-hearts

-- ==== 1. melee contact drains half a heart per invulnerability window ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local melee
  for _, e in ipairs(g.ctx.ents.enemies) do
    if e.type == "melee" then melee = e break end
  end
  -- stand the player in the melee's path and pin the melee overlapping
  -- it every step (resolve happens inside update; the pin guarantees
  -- contact regardless of the patrol)
  local hp_seen = {}
  for step = 1, 250 do
    p.x, p.y, p.vx, p.vy = 330, 106, 0, 0
    melee.x, melee.y, melee.vx, melee.vy = 326, 104, 0, 0
    env.love.update(1/30)
    env.love.draw()
    if p.hp ~= hp_seen[#hp_seen] then
      hp_seen[#hp_seen + 1] = p.hp
      hp_seen["at" .. #hp_seen] = step
    end
    if p.hp == max_hp() and #hp_seen >= max_hp() then break end  -- died and respawned
  end
  -- drained 6 -> 5 -> 4 -> ... one half-heart per invulnerability window
  assert_true(#hp_seen >= 3,
    "melee contact drains health one half-heart at a time (saw "
    .. #hp_seen .. " values)")
  assert_true(hp_seen[1] == 5 and hp_seen[2] == 4,
    "health goes 6 -> 5 -> 4 under repeated contact")
  local invuln = g.ctx.config.player.invuln_steps
  assert_true(hp_seen.at2 - hp_seen.at1 >= invuln,
    "the second half-heart is only lost after i-frames lapse (gap "
    .. (hp_seen.at2 - hp_seen.at1) .. ")")
end

-- ==== 2. an enemy arrow hit costs half a heart ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 360, 74)
  -- dart straight at the player (slow enough to land inside the box)
  table.insert(g.ctx.ents.e_arrows, {
    x = 352, y = 77, vx = 4, vy = 0, active = true,
  })
  run_steps(env, 6)
  assert_true(p.hp == max_hp() - 1,
    "an arrow hit costs half a heart (hp now " .. tostring(p.hp) .. ")")
  assert_true(p.invuln > 0, "the hit grants invulnerability frames")
end

-- ==== 3. the last half-heart lost is fatal and refills on respawn ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.hp = 1
  place_player(g, 360, 74)
  local before_x, before_y = p.x, p.y
  table.insert(g.ctx.ents.e_arrows, {
    x = 352, y = 77, vx = 4, vy = 0, active = true,
  })
  run_steps(env, 6)
  assert_true(p.hp == max_hp(), "respawn refills health to full")
  assert_true(p.invuln == 0, "respawn clears invulnerability")
  assert_true(p.x ~= before_x or p.y ~= before_y,
    "the fatal hit respawned the player")
end

-- ==== 4. falling off the world is instant death ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.hp = 2
  p.y = g.ctx.world.px_h + 40
  run_steps(env, 3)
  assert_true(p.hp == max_hp(),
    "the void kills outright and respawns at full health")
end

print(("player tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
