-- Enemy behaviour tests (deterministic, headless; requires LuaJIT).
--
-- Covers the archers' sense -> aim -> volley brain and the shared
-- track/cover-fire/investigate loop:
--   1. the player behind the archer is not spotted (back turned)
--   2. the player behind terrain is not spotted (no x-ray vision)
--   3. the player out of range is not spotted
--   4. spotting enters the aim state (aim fields set)
--   5. aim expiry fires a spread volley of three arrows and cools down
--   6. losing sight mid-aim: fires anyway, then covers the last known
--      spot until the window lapses, then investigates the last known
--      position -- walking off its platform if it must
--   7. investigate ends on arrival
-- plus patrol roaming and the archer's platform instincts:
--   8. an enemy on flat ground never patrols beyond roam_tiles from
--      its spawn point
--   9. investigating enemies may leave their roam limit
--  10. rapid-fire cadence repeats while the player stays visible
--  11. losing the player during the rapid-fire wait opens cover fire
--  12. drops deeper than max_drop_tiles end the investigate search
--  13. a backed archer on a small platform holds the edge, no pacing
-- plus the test menu's enemies toggle:
--  14. toggling off disarms the enemy systems (no updates, arrows
--      cleared, archers reset) but the enemies list itself is kept --
--      they are simply invisible until toggled back on
-- plus the shared smarter-AI model:
--  15. cover fire: blind volleys fly toward the last known position,
--      the archer holds its ground, and re-spotting returns to combat
--  16. the last known position tracks the visible player in every
--      state (patrol and the rapid-fire wait included)
--  17. an investigating archer re-engages on sight regardless of its
--      shoot cooldown
-- and the melee brain:
--  18. a spotted player is chased at melee_chase_speed; losing sight
--      switches to a patrol-pace search that ends on arrival; seeing
--      the player again returns to the chase
--  19. a chase gives up rather than stepping off a deep drop
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

local function melee(game)
  for _, e in ipairs(game.ctx.ents.enemies) do
    if e.type == "melee" then return e end
  end
end

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- Warm-up for far-from-spawn enemies: pins both bodies while the boot
-- camera pans to the player, so sight checks and simulation culling are
-- settled before the free-running assertions.
local function settle(env, g, e, ex, ey, px, py, n)
  for _ = 1, n or 18 do
    env.love.update(1/30)
    env.love.draw()
    e.x, e.y, e.vx, e.vy = ex, ey, 0, 0
    place_player(g, px, py)
  end
end

-- ==== 1. back turned ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  place_player(g, 720, 148)  -- clear line of sight
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
  -- in front and in range (~116px), but the platform floor blocks the ray
  place_player(g, 780, 228)
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
  place_player(g, 1000, 228)  -- ~330px away
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
  place_player(g, 720, 148)
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
  place_player(g, 720, 148)
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
    -- first volley observed: stop sampling (with a fast aim the rapid
    -- cadence can start a second volley inside a longer window)
    if spawns >= 3 then break end
  end
  assert_true(spawns == 3, "volley releases exactly three arrows (got " .. spawns .. ")")
  assert_true(max_jump == 1, "volley arrows are staggered one at a time")
  assert_true(e.shoot_cd > 0, "volley starts the shoot cooldown")
  table.sort(angles)
  assert_true(#angles == 3 and angles[1] < angles[2] and angles[2] < angles[3],
    "volley arrows fly at three distinct angles")
end

-- ==== 6. lost sight mid-aim: fire anyway, cover fire, then investigate ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 720, 148)
  run_steps(env, 5)
  assert_true(e.state == "aim", "archer enters aim")
  -- hide the player: below-right, in front but with no line of sight
  place_player(g, 780, 228)
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
  assert_true(e.state == "suppress", "losing the player opens the cover-fire window")
  assert_true(e.suppress_t ~= nil and e.suppress_t > 0
    and e.suppress_t <= config.enemies.suppress_steps,
    "the cover-fire window is bounded (" .. tostring(e.suppress_t) .. ")")
  assert_true(e.last_known.x < 730 and e.last_known.y < 160,
    "cover fire aims at the last seen spot, not the hidden player")

  -- the window lapsing hands the search over
  e.suppress_t = 2
  local investigated = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "investigate" then investigated = true break end
  end
  assert_true(investigated,
    "the cover-fire window lapsing starts the investigation")

  -- last known spot well beyond its platform's edge (platform floor
  -- top is y=160, platform spans px 656-736): the search must walk it
  -- off the edge rather than stopping at the ledge
  e.last_known = { x = e.x + 120, y = e.y }
  local left_platform = false
  for _ = 1, 300 do
    env.love.update(1/30)
    env.love.draw()
    -- below the platform the body's y grows past 84, past the edge x
    -- grows past 368
    if e.y > 168 and e.x > 736 then left_platform = true break end
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
  e.last_known = { x = e.x + 4, y = e.y }  -- practically arrived
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
  -- teleport onto the long flat floor (px 1072-1376, ground top y=240)
  -- with its spawn as home anchor: the roam limit (10 tiles = 160px)
  -- must turn it around long before the floor's far edge (688)
  melee.x, melee.y, melee.vx, melee.vy = 1120, 224, 0, 0
  melee.home_x = 1120
  melee.facing = 1
  -- behind the left wall block (x 1024..1088), so the new chase brain
  -- never spots it and the pure patrol/roam behaviour is what's tested
  place_player(g, 1000, 228)
  local max_x = 0
  for _ = 1, 400 do
    env.love.update(1/30)
    env.love.draw()
    max_x = math.max(max_x, melee.x)
  end
  assert_true(melee.home_x + config.enemies.roam_tiles * config.tile_size
    + melee.w + 4 > max_x,
    "melee on flat ground turns at its roam limit (max x "
    .. math.floor(max_x) .. ")")
end

-- ==== 9. investigate ignores the roam limit ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  -- the player parks far right of the search path, out of sight for
  -- the whole walk (a re-spot returns to combat and would end the walk)
  place_player(g, 1440, 228)
  e.state = "investigate"
  e.investigate_t = 400
  e.last_known = { x = e.x + 400, y = e.y }
  local beyond = false
  for _ = 1, 400 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "investigate" and e.x > e.home_x + config.enemies.roam_tiles * config.tile_size then
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
  place_player(g, 720, 148)
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

-- ==== 11. losing the player during the wait opens cover fire ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local game_enemies = env.require("src.enemies")
  local real_spawn = game_enemies.spawn_e_arrow
  game_enemies.spawn_e_arrow = function() end
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 720, 148)
  local entered = false
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "wait" then entered = true break end
  end
  assert_true(entered, "archer enters the rapid-fire wait")
  -- the player vanishes (LOS blocked below-right)
  place_player(g, 780, 228)
  local covered = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "suppress" then covered = true break end
  end
  assert_true(covered,
    "losing the player during the wait opens the cover-fire window")
  assert_true(e.suppress_t ~= nil
    and e.suppress_t <= config.enemies.suppress_steps,
    "the cover-fire window is set")
  -- the window lapsing hands the search over
  e.suppress_t = 2
  local investigated = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "investigate" then investigated = true break end
  end
  game_enemies.spawn_e_arrow = real_spawn
  assert_true(investigated,
    "the cover-fire window lapsing triggers the investigation")
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
  e.last_known = { x = e.x + 200, y = e.y }  -- past the shelf edge
  local gave_up = false
  for _ = 1, 300 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "patrol" then
      gave_up = e.x < e.home_x + 40 and e.y <= 88
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

-- ==== 14. the test menu's enemies toggle ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  place_player(g, 720, 148)  -- clear line of sight
  e.shoot_cd = 0
  e.facing = 1
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "wait" then break end  -- the aim fired its volley
  end
  assert_true(e.state == "wait" and e.shoot_cd > 0,
    "the archer aimed and fired before the toggle")
  -- plus a synthetic dart in flight
  table.insert(g.ctx.ents.e_arrows, { x = 704, y = 154, vx = 8, vy = 0,
    active = true })

  g:toggle_enemies()
  assert_true(not g.ctx.config.enemies.enabled,
    "the toggle turns the enemies off")
  assert_true(#g.ctx.ents.enemies > 0,
    "the enemies list is kept (they are invisible, not removed)")
  assert_true(#g.ctx.ents.e_arrows == 0,
    "enemy arrows vanish when the enemies are toggled off")
  assert_true(e.state == "patrol" and e.aim_vx == nil and e.volley == nil,
    "a mid-shot archer drops back to patrol")
  -- nothing resumes while off: the frozen enemies never move or shoot
  local frozen_x = e.x
  for _ = 1, 30 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(e.x == frozen_x and #g.ctx.ents.e_arrows == 0,
    "disabled enemies stay frozen and fire nothing")

  g:toggle_enemies()
  assert_true(g.ctx.config.enemies.enabled,
    "the toggle turns the enemies back on")
  -- a visible player is spotted again after re-enabling
  place_player(g, 720, 148)
  e.shoot_cd = 0
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "aim" then break end
  end
  assert_true(e.state == "aim", "archers resume hunting after re-enabling")
end

-- ==== 15. cover fire: blind shots at the last known position ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  -- record shot releases instead of flying real arrows
  local game_enemies = env.require("src.enemies")
  local shots = {}
  game_enemies.spawn_e_arrow = function(ctx, x, y, angle)
    shots[#shots + 1] = { x = x, y = y, angle = angle }
  end
  local e = archer(g)
  e.shoot_cd = 0
  e.facing = 1
  place_player(g, 720, 148)
  run_steps(env, 5)
  assert_true(e.state == "aim", "archer enters aim")
  -- sight breaks mid-aim (player hides below-right)
  place_player(g, 780, 228)
  local covered = false
  for _ = 1, 80 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "suppress" then covered = true end
    if covered and #shots >= 3 then break end  -- first volley completes
  end
  assert_true(covered, "sight loss mid-aim opens the cover-fire window")
  assert_true(#shots >= 3, "the first blind volley released (" .. #shots .. ")")
  local known = { x = e.last_known.x, y = e.last_known.y }
  assert_true(known.x < 730 and known.y < 160,
    "the tracked spot is the last seen position")
  for _, shot in ipairs(shots) do
    local want = math.atan2(known.y - shot.y, known.x - shot.x)
    assert_true(math.abs(shot.angle - want) < 0.25,
      "each blind shot flies toward the last known position (angle "
      .. string.format("%.3f", shot.angle) .. " vs "
      .. string.format("%.3f", want) .. ")")
  end
  -- covering means holding ground, not walking
  local x0 = e.x
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(math.abs(e.x - x0) < 2,
    "the covering archer holds its ground (drift "
    .. string.format("%.2f", math.abs(e.x - x0)) .. ")")
  -- seeing the player again returns to combat at once
  place_player(g, 720, 148)
  run_steps(env, 3)
  assert_true(e.state == "aim", "re-spotting returns the archer to combat")
  assert_true(e.suppress_t == nil, "the cover-fire window is closed")
end

-- ==== 16. the last known position tracks the visible player ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local game_enemies = env.require("src.enemies")
  local real_spawn = game_enemies.spawn_e_arrow
  game_enemies.spawn_e_arrow = function() end
  local e = archer(g)
  e.facing = 1
  -- patrol with the cooldown up: the player is watched but not engaged
  e.shoot_cd = 999
  place_player(g, 720, 148)
  run_steps(env, 3)
  assert_true(e.state == "patrol", "a cooled-down archer stays on patrol")
  assert_true(e.last_known ~= nil
    and math.abs(e.last_known.x - 724) < 2
    and math.abs(e.last_known.y - 154) < 2,
    "patrol tracks the visible player's position")
  place_player(g, 700, 148)
  run_steps(env, 3)
  assert_true(math.abs(e.last_known.x - 704) < 2,
    "the tracked spot follows the moving player")
  -- and during the rapid-fire wait
  e.shoot_cd = 0
  place_player(g, 720, 148)
  for _ = 1, 60 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "wait" then break end
  end
  assert_true(e.state == "wait", "archer is mid-cadence")
  place_player(g, 740, 148)
  run_steps(env, 3)
  assert_true(math.abs(e.last_known.x - 744) < 2,
    "the rapid-fire wait keeps tracking the visible player")
  game_enemies.spawn_e_arrow = real_spawn
end

-- ==== 17. an investigating archer re-engages on sight ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = archer(g)
  e.facing = 1
  e.shoot_cd = 999  -- the old cooldown gate would stall the re-engagement
  e.state = "investigate"
  e.investigate_t = 100
  e.last_known = { x = e.x + 8, y = e.y }  -- practically arrived
  place_player(g, 720, 148)  -- visible in front
  run_steps(env, 3)
  assert_true(e.state == "aim",
    "an investigating archer re-engages on sight despite the cooldown")
end

-- ==== 18. the melee brain: chase, search, re-chase, settle ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = melee(g)
  -- settle the camera on the pair first: the melee sits far from the
  -- boot screen and would be simulation-culled; home_x is re-anchored
  -- to the perch so patrol's roam flip can't blind it to the player
  e.home_x = 1136
  e.facing = 1  -- face the player
  settle(env, g, e, 1136, 224, 1240, 228)
  assert_true(e.state == "chase", "a spotted player is chased")
  local x0 = e.x
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
  end
  local gained = e.x - x0
  assert_true(gained > 40,
    "the chase closes in on the player (" .. string.format("%.1f", gained) .. "px)")
  assert_true(math.abs(gained / 20 - config.enemies.melee_chase_speed) < 0.5,
    "the chase sprints at melee_chase_speed")
  -- sight breaks: the search begins at the last tracked spot
  place_player(g, 1000, 228)  -- behind the left wall, out of sight
  run_steps(env, 3)
  assert_true(e.state == "investigate",
    "losing sight switches the chase to a search")
  assert_true(e.last_known ~= nil and e.last_known.x > 1230,
    "the search heads for the last tracked spot")
  for _ = 1, 80 do
    env.love.update(1/30)
    env.love.draw()
    if e.state == "patrol" then break end
  end
  assert_true(e.state == "patrol", "the search ends on arrival")
  -- and seeing the player again returns to the chase immediately
  e.state = "investigate"
  e.investigate_t = 200
  e.last_known = { x = e.x + 200, y = e.y }  -- searching rightward
  place_player(g, 1300, 228)  -- visible, but out of contact reach
  run_steps(env, 3)
  assert_true(e.state == "chase", "re-spotting returns the melee to the chase")
end

-- ==== 19. the chase gives up at a deep drop ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = melee(g)
  -- the small island (px 1936..1984) ends in a 32px gap whose floor is
  -- 240px down (far deeper than max_drop_tiles); the player stands
  -- across it, well within detect range
  e.home_x = 1952
  e.facing = 1  -- face the player across the gap
  settle(env, g, e, 1952, 224, 2020, 228)
  assert_true(e.state == "chase", "the player is spotted across the gap")
  for _ = 1, 40 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(e.x > 1950, "the chase advanced toward the gap")
  assert_true(e.x + e.w < 1990,
    "the chase never steps off into the gap (x "
    .. string.format("%.1f", e.x) .. ")")
end

print(("enemy tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
