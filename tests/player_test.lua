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
--   5. jump corner forgiveness: a one-corner head clip slides around
--      the ledge instead of killing the jump; overhangs still bump
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

-- ==== 5. jump corner forgiveness ====
-- Rigs a ceiling tile at (6,9): x 48..55, y 72..79. The player (4px
-- wide) placed at x=45 has only its right head corner inside the tile's
-- column, so rising into row 9 clips the ledge's edge corner.
local function rig_ledge(g)
  local w = g.ctx.world
  local solid_id = w:tile(0, 14)  -- the spawn-area wall/floor tile id
  w:set_tile(6, 9, solid_id)
  return w
end

do
  -- one-corner clip: the player slides around the ledge and keeps the
  -- full jump height (velocity preserved, never bumped)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  place_player(g, 45, 80)
  p.gr = false
  p.vy = -3
  run_steps(env, 1)
  assert_true(p.vy < 0, "the corner clip did not kill the jump (vy "
    .. p.vy .. ")")
  assert_true(p.x == 44, "the player slid around the corner (x "
    .. p.x .. ")")
  run_steps(env, 8)
  assert_true(p.y < 72, "the jump reached its full height above the "
    .. "ledge (y " .. p.y .. ")")
end
do
  -- an overhang covering both head corners still bumps normally
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  place_player(g, 49, 80)  -- box 49..52: both corners under the ledge
  p.gr = false
  p.vy = -2
  run_steps(env, 1)
  assert_true(p.vy == 0, "a covered head bump zeroes the velocity")
  assert_true(p.y == 80, "the bump snaps the player below the ledge")
end
do
  -- a slide deeper than the nudge cap refuses and bumps
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  g.ctx.config.player.corner_nudge_px = 1  -- this clip needs a 2px slide
  place_player(g, 46, 80)  -- box 46..49: right corner clips 2px deep
  p.gr = false
  p.vy = -2
  run_steps(env, 1)
  assert_true(p.vy == 0, "a slide past the nudge cap bumps instead")
  assert_true(p.y == 80, "the refused nudge snapped below the ledge")
end

print(("player tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
