-- Enemy behaviour tests (deterministic, headless; requires LuaJIT).
--
-- Covers the archers' sense -> aim -> volley -> investigate brain:
--   1. the player behind the archer is not spotted (back turned)
--   2. the player behind terrain is not spotted (no x-ray vision)
--   3. the player out of range is not spotted
--   4. spotting enters the aim state (aim fields set)
--   5. aim expiry fires a spread volley of three arrows and cools down
--   6. losing sight mid-aim: fires anyway, then investigates the last
--      known position -- walking off its platform if it must
--   7. investigate ends on arrival
-- plus patrol roaming and the archer's platform instincts:
--   8. an enemy on flat ground never patrols beyond roam_tiles from
--      its spawn point
--   9. investigating enemies may leave their roam limit
--  10. rapid-fire cadence repeats while the player stays visible
--  11. losing the player during the rapid-fire wait triggers investigate
--  12. drops deeper than max_drop_tiles end the investigate search
--  13. a backed archer on a small platform holds the edge, no pacing
--
-- Usage (from the project root): luajit tests/enemies_test.lua

local Harness = dofile("tests/harness.lua")

local Enemies = dofile("src/enemies.lua")
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

local function fresh_game()
  local keys, quit = {}, { false }
  local env = Harness.new_env(keys, quit)
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  env.love.load()
  return env
end

local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

local function archer(game)
  for _, e in ipairs(game.ctx.ents.enemies) do
    if e.type == "archer" then return e end
  end
end

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- ==== 1. back turned ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  place_player(g, 360, 74)  -- clear line of sight
  e.facing = -1
  assert_true(not Enemies.sees(g.ctx, e),
    "archer must not see a player standing behind it")
  e.facing = 1
  assert_true(Enemies.sees(g.ctx, e),
    "archer sees a player in front of it with clear line of sight")
end

-- ==== 2. terrain blocks vision ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  -- in front and in range (67px), but the platform floor blocks the ray
  place_player(g, 390, 114)
  run_steps(env, 60)
  assert_true(e.state ~= "aim", "archer must not aim through terrain")
  assert_true(#g.ctx.ents.e_arrows == 0, "no volley without line of sight")
end

-- ==== 3. out of range ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 500, 114)  -- ~165px away
  run_steps(env, 60)
  assert_true(e.state ~= "aim", "archer must not aim beyond its sight range")
end

-- ==== 4. spotting enters the aim state ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 360, 74)
  run_steps(env, 5)
  assert_true(e.state == "aim", "archer must aim once the player is spotted")
  assert_true(e.aim_t ~= nil and e.aim_t > 0, "aim has a preparation timer")
  assert_true(e.aim_vx ~= nil and e.aim_vy ~= nil, "aim solves a launch velocity")
  assert_true(e.last_known ~= nil, "aim tracks the player's position")
end

-- ==== 5. aim expiry fires a staggered volley ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 360, 74)
  -- watch the volley spawn: sample the arrow list every step and count
  -- each increase as one arrow released (arrows may die before all
  -- three are airborne at once, so absolute counts are unreliable)
  local spawns, max_jump, prev = 0, 0, 0
  local angles = {}
  local wait_checked = false
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    local n = #g.ctx.ents.e_arrows
    if n > prev then
      spawns = spawns + (n - prev)
      max_jump = math.max(max_jump, n - prev)
      local newest = g.ctx.ents.e_arrows[n]
      if newest then
        angles[#angles+1] = math.atan2(newest.vy, newest.vx)
      end
      if not wait_checked then
        wait_checked = true
        assert_true(e.state == "wait",
          "aiming archer waits for the follow-up cadence after firing")
        assert_true(e.wait_t ~= nil
          and e.wait_t >= config.enemies.rapid_min
          and e.wait_t <= config.enemies.rapid_min + config.enemies.rapid_extra,
          "follow-up wait is randomized within the rapid window ("
          .. tostring(e.wait_t) .. ")")
      end
    end
    prev = n
  end
  assert_true(spawns == 3, "volley releases exactly three arrows (got " .. spawns .. ")")
  assert_true(max_jump == 1, "volley arrows are staggered one at a time")
  assert_true(e.shoot_cd > 0, "volley starts the shoot cooldown")
  table.sort(angles)
  assert_true(#angles == 3 and angles[1] < angles[2] and angles[2] < angles[3],
    "volley arrows fly at three distinct angles")
end

-- ==== 6. lost sight mid-aim: fire anyway + investigate ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 360, 74)
  run_steps(env, 5)
  assert_true(e.state == "aim", "archer enters aim")
  -- hide the player: below-right, in front but with no line of sight
  place_player(g, 390, 114)
  local fired = false
  local spawns, prev = 0, 0
  for _ = 1, 40 do
    env.love.update(1/30)
    env.love.draw()
    local n = #g.ctx.ents.e_arrows
    if n > prev then spawns = spawns + (n - prev) end
    prev = n
    if spawns >= 3 then fired = true break end
  end
  assert_true(fired, "archer fires anyway once the player is lost mid-aim")
  assert_true(e.state == "investigate", "archer investigates after losing the player")

  -- last known spot well beyond its platform's edge (platform floor
  -- top is y=80, platform spans px 328-368): the search must walk it
  -- off the edge rather than stopping at the ledge
  e.last_known = { x = e.x + 60, y = e.y }
  local left_platform = false
  for _ = 1, 300 do
    env.love.update(1/30)
    env.love.draw()
    -- below the platform the body's y grows past 84, past the edge x
    -- grows past 368
    if e.y > 84 and e.x > 368 then left_platform = true break end
    if e.state == "patrol" then break end
  end
  assert_true(left_platform,
    "investigating archer walks off its platform toward the last known spot")
end

-- ==== 7. investigate ends ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.state = "investigate"
  e.investigate_t = 30
  e.last_known = { x = e.x + 2, y = e.y }  -- practically arrived
  run_steps(env, 40)
  assert_true(e.state == "patrol", "investigate ends on reaching the last known spot")
end

-- ==== 8. patrol roam limit ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local melee
  for _, e in ipairs(g.ctx.ents.enemies) do
    if e.type == "melee" then melee = e break end
  end
  -- teleport onto the long flat floor (px 536-688, ground top y=120)
  -- with its spawn as home anchor: the roam limit (10 tiles = 80px)
  -- must turn it around long before the floor's far edge (688)
  melee.x, melee.y, melee.vx, melee.vy = 560, 112, 0, 0
  melee.home_x = 560
  melee.facing = 1
  place_player(g, 450, 114)  -- nearby, so camera culling keeps it simulated
  local max_x = 0
  for _ = 1, 400 do
    env.love.update(1/30)
    env.love.draw()
    max_x = math.max(max_x, melee.x)
  end
  assert_true(melee.home_x + 80 + melee.w + 2 > max_x,
    "melee on flat ground turns at its roam limit (max x "
    .. math.floor(max_x) .. ")")
end

-- ==== 9. investigate ignores the roam limit ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 400  -- cannot re-spot: no aim interruption
  e.state = "investigate"
  e.investigate_t = 400
  e.last_known = { x = e.x + 200, y = e.y }
  local beyond = false
  for _ = 1, 400 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "investigate" and e.x > e.home_x + 80 then
      beyond = true break
    end
    if e.state == "patrol" then break end
  end
  assert_true(beyond,
    "investigating enemy walks past its patrol roam limit")
end

-- ==== 10. rapid-fire cadence while the player stays visible ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  -- suppress live arrows so the (stationary) player survives the loop;
  -- the cadence state machine is what's under test here
  local game_enemies = env.require("src.enemies")
  local real_spawn = game_enemies.spawn_e_arrow
  game_enemies.spawn_e_arrow = function() end
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 360, 74)
  local waits = {}
  local last_state = e.state
  for _ = 1, 300 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "wait" and last_state ~= "wait" then
      waits[#waits+1] = e.wait_t
    end
    last_state = e.state
  end
  game_enemies.spawn_e_arrow = real_spawn
  assert_true(#waits >= 2,
    "rapid fire repeats while the player stays visible (" .. #waits .. " volleys)")
  for _, wt in ipairs(waits) do
    assert_true(wt >= config.enemies.rapid_min
      and wt <= config.enemies.rapid_min + config.enemies.rapid_extra,
      "each follow-up wait is within the randomized range (" .. wt .. ")")
  end
end

-- ==== 11. losing the player during the wait triggers investigate ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local game_enemies = env.require("src.enemies")
  local real_spawn = game_enemies.spawn_e_arrow
  game_enemies.spawn_e_arrow = function() end
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 360, 74)
  local entered = false
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "wait" then entered = true break end
  end
  assert_true(entered, "archer enters the rapid-fire wait")
  -- the player vanishes (LOS blocked below-right)
  place_player(g, 390, 114)
  local investigated = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "investigate" then investigated = true break end
  end
  game_enemies.spawn_e_arrow = real_spawn
  assert_true(investigated,
    "losing the player during the wait triggers investigate")
end

-- ==== 12. deep drops end the investigate search ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  -- the second archer sits on a high shelf: the ground below its edge
  -- is a 9-tile drop to the long row-15 floor, far deeper than
  -- max_drop_tiles (4) -- investigating past the edge must be refused
  local e
  local n = 0
  for _, en in ipairs(g.ctx.ents.enemies) do
    if en.type == "archer" then
      n = n + 1
      if n == 2 then e = en break end
    end
  end
  assert_true(e ~= nil, "level has a second archer")
  e.shoot_cd = 9999  -- cannot re-spot: no aim interruption
  e.state = "investigate"
  e.investigate_t = 900
  e.last_known = { x = e.x + 100, y = e.y }  -- past the shelf edge
  local gave_up = false
  for _ = 1, 300 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "patrol" then
      gave_up = e.x < e.home_x + 20 and e.y <= 44
      break
    end
  end
  assert_true(gave_up,
    "archer refuses drops deeper than max_drop_tiles and stays on its shelf")
end

-- ==== 13. small backed perch: hold the edge, don't pace ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  -- the second archer sits on a narrow shelf with the tall pillar
  -- immediately behind it: it may walk out to the edge once, but must
  -- then hold position instead of pacing back and forth
  local e
  local n = 0
  for _, en in ipairs(g.ctx.ents.enemies) do
    if en.type == "archer" then
      n = n + 1
      if n == 2 then e = en break end
    end
  end
  assert_true(e ~= nil, "level has a second archer")
  for _ = 1, 20 do  -- let it settle at the edge
    env.love.update(1/30)
    env.love.draw()
  end
  local min_x, max_x = e.x, e.x
  for _ = 1, 120 do
    env.love.update(1/30)
    env.love.draw()
    min_x = math.min(min_x, e.x)
    max_x = math.max(max_x, e.x)
  end
  assert_true(max_x - min_x < 0.5,
    "backed archer holds the edge instead of pacing (range "
    .. string.format("%.2f", max_x - min_x) .. ")")
end

print(("enemy tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
