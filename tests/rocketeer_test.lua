-- Rocketeer behaviour tests (deterministic, headless; requires LuaJIT).
--
-- A synthetic rocketeer is inserted onto a stable platform (the wide
-- upper platform, body top 208 / feet 224 -- committed terrain with a
-- clear vertical shaft above, so rocket climbs are not cut short by the
-- level's own geometry). All other level enemies are dropped per test,
-- so no stray archer or laser can confound health assertions.
--
-- The rocketeer shares the ranged brain (see -> blink-aim -> fire ->
-- wait/investigate) but lobs its ordnance straight up:
--   1. spotting the player enters the aim state (telegraph timer set)
--   2. the blink telegraph launches a rocket just above the head,
--      flying straight up (a small jitter aside)
--   3. the climb ends in a hover above the shooter; it hangs there
--      without drifting, then turns on a dime: the heading snaps at
--      the player's live position
--   4. the rocket hunts the player behind the shooter's back -- sight
--      does not gate a rocket in flight (cover is no protection)
--   5. the fuse detonates near the player: a full heart, i-frames set
--   6. terrain contact detonates: a ceiling shot flashes just short of
--      the wall and hurts nobody far away
--   7. a player arrow tip detonates a rocket (arrow consumed), and the
--      blast kills an enemy caught in the radius
--   8. rockets come in bursts: rocket_burst_count per charge on the
--      short burst cadence, then the long recharge (like the laser)
--   9. the airborne cap drops excess launches
--  10. the test menu's enemies toggle disarms a firing rocketeer and
--      clears rockets in flight
--
-- Usage (from the project root): luajit tests/rocketeer_test.lua

local Harness = dofile("tests/harness.lua")

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

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- Builds a rocketeer with the level spawn's full field set.
local function make_rocketeer(game, x, y)
  local cfg = game.ctx.config.enemies
  local e = {
    x = x, y = y, home_x = x,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, type = "rocketeer",
    shoot_cd = 0, spr = 138, rot = nil,
    state = "patrol", aim_t = 0, last_known = nil,
  }
  table.insert(game.ctx.ents.enemies, e)
  return e
end

-- Drops every other enemy so no stray archer/laser can fire into the
-- test's health assertions.
local function drop_other_enemies(g, e)
  local list = g.ctx.ents.enemies
  for i = #list, 1, -1 do
    if list[i] ~= e then table.remove(list, i) end
  end
end

-- Test perches on stable, committed terrain:
--   the wide upper platform (body top 208, feet 224) has a clear
--   vertical shaft above (solid sky ceiling far up at y=30). Its right
--   end carries spring pads whose solid band (y 216..223) blocks a
--   horizontal sight ray, so the combat spot hangs directly overhead
--   instead: visible, in the facing half-plane, and the launch shaft
--   stays clear all the way up.
local PERCH_X, PERCH_Y = 440, 208
local SPOT_X, SPOT_Y = 444, 96  -- directly overhead, ~112px up

-- Per-step position hold: keeps the rocketeer on its perch without
-- touching its timers.
local function hold_rocketeer(g, e, x, y)
  e.x, e.y, e.vx, e.vy = x, y, 0, 0
end

-- Warm-up: pins both bodies a few steps so the sight picture is stable.
local function settle(env, g, e, x, y, n, px, py)
  for _ = 1, n or 8 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
  end
end

-- Runs steps until the telegraph launches a rocket (then one more, so
-- the rocket's first full flight tick has processed). Pins both bodies
-- every step. Returns the live rocket, or nil if nothing launched.
local function fire_first_rocket(env, g, e, x, y, px, py)
  for _ = 1, math.ceil(config.enemies.rocket_aim_steps) + 6 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
    if #g.ctx.ents.rockets > 0 then
      env.love.update(1/30)
      env.love.draw()
      hold_rocketeer(g, e, x, y)
      place_player(g, px or SPOT_X, py or SPOT_Y)
      return g.ctx.ents.rockets[1]
    end
  end
  return nil
end

-- ==== 1. spotting enters the aim state ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y, 2)
  assert_true(e.state == "aim", "the rocketeer aims once the player is spotted")
  assert_true(e.aim_t ~= nil and e.aim_t > 0
    and e.aim_t <= config.enemies.rocket_aim_steps,
    "the aim has a blink-telegraph timer")
  assert_true(e.last_known ~= nil, "the aim tracks the player's position")
  assert_true(e.facing == 1, "the rocketeer faces its aim")
  assert_true(#g.ctx.ents.rockets == 0,
    "nothing launches while the telegraph still blinks")
end

-- ==== 2. the telegraph launches a rocket straight up ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y, 3)
  assert_true(e.state == "aim", "the rocketeer is mid-telegraph")
  local r = fire_first_rocket(env, g, e, PERCH_X, PERCH_Y)
  assert_true(r ~= nil, "the blink-aim ends in a launched rocket")
  assert_true(r.state == "climb", "the rocket is climbing")
  assert_true(r.hy < -0.9, "the rocket climbs (heading up, hy " .. r.hy .. ")")
  assert_true(math.abs(r.hx) < 0.2,
    "the launch is straight up but for the jitter (hx " .. r.hx .. ")")
  assert_true(r.y < PERCH_Y and math.abs(r.x - (PERCH_X + 6)) < 4,
    "the rocket is just above the shooter's head")
  assert_true(e.state == "wait", "the rocketeer waits for its cadence after firing")
  assert_true(e.shoot_cd > 0, "firing starts the shoot cooldown")
end

-- ==== 3. the rocket hovers above the shooter, then turns on a dime ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y)
  local r = fire_first_rocket(env, g, e, PERCH_X, PERCH_Y)
  assert_true(r ~= nil, "the rocketeer launched")
  -- the climb carries it rocket_hover_height above the launch point
  local hover_y = nil
  for _ = 1, math.ceil(config.enemies.rocket_hover_height
      / config.enemies.rocket_speed) + 2 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if r.state == "hover" then hover_y = r.y break end
  end
  assert_true(hover_y ~= nil, "the climb ends in a hover")
  assert_true(hover_y <= PERCH_Y - config.enemies.rocket_hover_height + 1,
    "the hover hangs above the shooter (y " .. hover_y .. ")")
  -- it hangs in place for the hover duration: position pinned, no drift
  local hx0, hy0 = r.x, r.y
  for _ = 1, math.ceil(config.enemies.rocket_hover_steps) - 2 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, SPOT_X, SPOT_Y)
    assert_true(r.state == "hover", "the rocket hangs for the hover duration")
  end
  assert_true(math.abs(r.x - hx0) < 1 and math.abs(r.y - hy0) < 1,
    "the hovering rocket holds its position (drift "
    .. string.format("%.1f, %.1f", r.x - hx0, r.y - hy0) .. ")")
  -- then it turns on a dime: the heading snaps at the live player
  env.love.update(1/30)
  env.love.draw()
  hold_rocketeer(g, e, PERCH_X, PERCH_Y)
  place_player(g, SPOT_X, SPOT_Y)
  env.love.update(1/30)
  env.love.draw()
  hold_rocketeer(g, e, PERCH_X, PERCH_Y)
  place_player(g, SPOT_X, SPOT_Y)
  assert_true(r.state == "attack", "the hover ends in the attack")
  local p = g.ctx.player
  local dx, dy = p.x + p.w/2 - r.x, p.y + p.h/2 - r.y
  local dl = math.sqrt(dx*dx + dy*dy)
  local dot = (r.hx*dx + r.hy*dy) / dl
  assert_true(dot > 0.95,
    "the snapped heading aims at the player (dot "
    .. string.format("%.3f", dot) .. ")")
end

-- ==== 4. the rocket hunts the player behind the shooter's back ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y)
  local r = fire_first_rocket(env, g, e, PERCH_X, PERCH_Y)
  assert_true(r ~= nil, "the rocketeer launched")
  -- the player slips behind the shooter's back mid-hover: sight is
  -- gone, but the rocket still snaps onto the live position (it must
  -- come around to the left) and detonates on them
  place_player(g, 300, 212)
  local snapped = false
  for _ = 1, math.ceil(config.enemies.rocket_hover_height
      / config.enemies.rocket_speed)
    + math.ceil(config.enemies.rocket_hover_steps) + 4 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, 300, 212)
    if r.state == "attack" and r.hx < -0.5 then snapped = true break end
  end
  assert_true(snapped,
    "the rocket turns on a dime toward the player behind the shooter")
end

-- ==== 4. the fuse detonates near the player: a full heart ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  -- back turned on the player overhead: the shooter never spots them,
  -- but a directly-spawned rocket still hunts the live position
  e.facing = -1
  place_player(g, 444, 96)
  settle(env, g, e, PERCH_X, PERCH_Y, 4, 444, 96)
  assert_true(e.state == "patrol", "the shooter never spots the player")
  local p = g.ctx.player
  local cx, cy = p.x + p.w/2, p.y + p.h/2
  local Rockets = env.require("src.rockets")
  Rockets.spawn(g.ctx, PERCH_X + 6, PERCH_Y - 4)
  local boomed = false
  for _ = 1, math.ceil((PERCH_Y - 4 - cy) / config.enemies.rocket_speed)
    + math.ceil(config.enemies.rocket_hover_steps) + 12 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, 444, 96)
    if #g.ctx.ents.booms > 0 then boomed = true break end
  end
  assert_true(boomed, "the fuse trips as the rocket closes on the player")
  local b = g.ctx.ents.booms[1]
  local bd = math.sqrt((b.x - cx)^2 + (b.y - cy)^2)
  assert_true(bd <= config.enemies.rocket_proximity + 4,
    "the flash lands within fuse range of the player ("
    .. string.format("%.1f", bd) .. "px)")
  local max_hp = config.player.hearts * 2
  assert_true(p.hp == max_hp - config.enemies.rocket_half_hearts,
    "the blast costs a full heart (hp " .. p.hp .. ")")
  assert_true(p.invuln > 0, "the blast grants i-frames")
  assert_true(#g.ctx.ents.rockets == 0, "the spent rocket is gone")
end

-- ==== 5. terrain contact detonates a ceiling shot ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  -- the long lower floor under the small mid platform: a rocket fired
  -- up from (310,364) climbs to its hover point, then attacks toward
  -- the player parked under the platform's shadow -- the attack path
  -- meets the platform's underside (~y 320) first
  place_player(g, 310, 275)
  local Rockets = env.require("src.rockets")
  Rockets.spawn(g.ctx, 310, 364)
  local boomed = false
  for _ = 1, 40 do
    env.love.update(1/30)
    env.love.draw()
    place_player(g, 310, 275)
    if #g.ctx.ents.booms > 0 then boomed = true break end
  end
  assert_true(boomed, "the rocket detonates on terrain contact")
  local b = g.ctx.ents.booms[1]
  assert_true(b.y >= 314 and b.y <= 326,
    "the flash lands just short of the ceiling (y " .. b.y .. ")")
  local max_hp = config.player.hearts * 2
  assert_true(g.ctx.player.hp == max_hp, "the distant player is unharmed")
  assert_true(#g.ctx.ents.rockets == 0, "the spent rocket is removed")
end

-- ==== 6. an arrow tip detonates a rocket; the blast kills enemies ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  place_player(g, 540, 212)
  settle(env, g, e, PERCH_X, PERCH_Y, 2)
  local max_hp = config.player.hearts * 2
  -- a rocket in open air with a dummy enemy right beside it
  local cfg = config.enemies
  local Rockets = env.require("src.rockets")
  Rockets.spawn(g.ctx, 446, 150)
  local dummy = {
    x = 440, y = 156, home_x = 440,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, type = "melee",
    shoot_cd = 0, spr = 105, rot = nil,
    state = "patrol", last_known = nil,
  }
  table.insert(g.ctx.ents.enemies, dummy)
  -- a player arrow arriving at the rocket's position from the left
  table.insert(g.ctx.ents.arrows, {
    x = 446, y = 150, vx = 2, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 100,
    kind = "normal", traveled = 0,
  })
  env.love.update(1/30)
  env.love.draw()
  assert_true(#g.ctx.ents.rockets == 0, "the arrow tip detonates the rocket")
  assert_true(#g.ctx.ents.booms == 1, "the detonation flashes once")
  local found = false
  for _, en in ipairs(g.ctx.ents.enemies) do
    if en == dummy then found = true end
  end
  assert_true(not found, "the blast kills the enemy caught in the radius")
  assert_true(g.ctx.player.hp == max_hp,
    "the player standing outside the blast is unharmed")
  assert_true(#g.ctx.ents.particles
    >= config.particles.boom_count + config.particles.poof_count
      + config.particles.blood_count,
    "the blast throws sparks, a poof and blood ("
    .. #g.ctx.ents.particles .. " particles)")
  run_steps(env, 2)
  assert_true(#g.ctx.ents.arrows == 0, "the arrow is consumed by the blast")
end

-- ==== 7. rockets come in bursts of burst_count per charge ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true  -- keep the pinned player alive all loop
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y)
  -- count launches exactly: wrap the shared module's spawn
  local Rockets = env.require("src.rockets")
  local real_spawn = Rockets.spawn
  local launches, charges = 0, 0
  Rockets.spawn = function(ctx, x, y)
    local r = real_spawn(ctx, x, y)
    if r then launches = launches + 1 end
    return r
  end
  local waits = {}
  local last_state = e.state
  for _ = 1, 700 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.state == "wait" and last_state ~= "wait" then
      waits[#waits + 1] = e.wait_t
      if e.wait_t >= config.enemies.rocket_rapid_min then
        -- the long recharge closes a charge: it must have held exactly
        -- the burst budget's worth of launches
        charges = charges + 1
        assert_true(launches == config.enemies.rocket_burst_count,
          "each charge launches " .. config.enemies.rocket_burst_count
          .. " rockets (charge " .. charges .. " held " .. launches .. ")")
        launches = 0
      end
    end
    last_state = e.state
  end
  assert_true(charges >= 2,
    "the rocketeer recharges into further bursts (" .. charges .. " charges)")
  for _, wt in ipairs(waits) do
    local burst = wt >= config.enemies.rocket_burst_min
      and wt <= config.enemies.rocket_burst_min + config.enemies.rocket_burst_extra
    local long = wt >= config.enemies.rocket_rapid_min
      and wt <= config.enemies.rocket_rapid_min + config.enemies.rocket_rapid_extra
    assert_true(burst or long,
      "each follow-up wait is either a burst gap or the full recharge ("
      .. wt .. ")")
  end
  -- burst launches must also track: the tracked spot matches the pinned
  -- player at every telegraph
  assert_true(e.last_known ~= nil
    and math.abs(e.last_known.x - (SPOT_X + 4)) < 2,
    "the burst launches keep tracking the player's live position")
end

-- ==== 8. the airborne cap drops excess launches ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  local cfg = config.enemies
  local Enemies = env.require("src.enemies")
  for _ = 1, cfg.rocket_max_alive do
    table.insert(g.ctx.ents.rockets, {
      x = PERCH_X + 6, y = 100,
      hx = 0, hy = -1,
      state = "hover", hover_t = cfg.rocket_lifetime,
      climbed = cfg.rocket_hover_height,
      active = true, lt = cfg.rocket_lifetime, trail_t = 1,
    })
  end
  Enemies.fire_rocket(g.ctx, e)
  assert_true(#g.ctx.ents.rockets == cfg.rocket_max_alive,
    "the cap blocks launches beyond rocket_max_alive")
  table.remove(g.ctx.ents.rockets)
  Enemies.fire_rocket(g.ctx, e)
  assert_true(#g.ctx.ents.rockets == cfg.rocket_max_alive,
    "a freed slot accepts the next launch")
end

-- ==== 9. the enemies toggle disarms a firing rocketeer ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true
  local e = make_rocketeer(g, PERCH_X, PERCH_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, PERCH_X, PERCH_Y)
  assert_true(fire_first_rocket(env, g, e, PERCH_X, PERCH_Y) ~= nil,
    "the rocketeer aimed and launched before the toggle")

  g:toggle_enemies()
  assert_true(not g.ctx.config.enemies.enabled, "the toggle turns the enemies off")
  assert_true(#g.ctx.ents.rockets == 0, "rockets in flight are cleared")
  assert_true(e.state == "patrol",
    "a mid-shot rocketeer drops back to patrol")
  local frozen_x = e.x
  for _ = 1, 30 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(e.x == frozen_x and #g.ctx.ents.rockets == 0,
    "disabled rocketeers stay frozen and launch nothing")

  g:toggle_enemies()
  assert_true(g.ctx.config.enemies.enabled, "the toggle turns the enemies back on")
  e.shoot_cd = 0  -- the frozen cooldown would outlast this check
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    hold_rocketeer(g, e, PERCH_X, PERCH_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.state == "aim" then break end
  end
  assert_true(e.state == "aim", "rocketeers resume hunting after re-enabling")
end

print(("rocketeer tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
