-- Bomber behaviour tests (deterministic, headless; requires LuaJIT).
--
-- A synthetic bomber is inserted onto a stable perch (the lower
-- corridor floor, px 224/body top y 368 -- committed terrain, so the
-- test geometry doesn't chase map edits of the level's own enemies).
--
-- The bomber shares the ranged brain (see -> blink-aim -> throw ->
-- wait/investigate) but lobs its ordnance in a straight line:
--   1. spotting the player enters the aim state (telegraph timer set)
--   2. the blink telegraph throws a bomb from just above the head,
--      flying a straight line at the tracked spot at bomb_speed, with
--      a crude jittered fuse (straight-line estimate ± bomb_fuse_error)
--   3. grenade behaviour over a grounded player: the burst lands on the
--      throw-time spot (fuse timing, not proximity), so a player who
--      dodges mid-flight is unharmed
--   4. flak behaviour over an airborne player: proximity to their live
--      centre bursts the bomb early (fuse still burning)
--   5. a grounded player is not proximity-burst at all: the bomb flies
--      straight through their box and burns its fuse elsewhere
--   6. terrain contact bounces the grenade body instead of detonating
--      (damped, reversed velocity), and the fuse pops later
--   7. a player arrow tip detonates a bomb (arrow consumed), and the
--      blast kills an enemy caught in the radius
--   8. bombs come in bursts: bomber_burst_count per charge on the short
--      burst cadence, then the long recharge (like the laser/rocketeer)
--   9. the airborne cap drops excess throws
--  10. the test menu's enemies toggle disarms a firing bomber and
--      clears bombs in flight
--
-- Usage (from the project root): luajit tests/bomber_test.lua

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

-- Builds a bomber with the level spawn's full field set.
local function make_bomber(game, x, y)
  local cfg = game.ctx.config.enemies
  local e = {
    x = x, y = y, home_x = x,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, type = "bomber",
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

-- Clears every enemy outright (for ordnance-only checks that need no
-- shooter and no interference).
local function clear_enemies(g)
  local list = g.ctx.ents.enemies
  for i = #list, 1, -1 do table.remove(list, i) end
end

-- Test perches on stable, committed terrain:
--   the lower corridor floor at (224,368); the corridor's east wall
--   (tiles at x 384..415) sits ~154px out, and a player standing
--   directly below the small mid platform at (512,304) is hidden
--   behind the platform tiles
local FLOOR_X, FLOOR_Y = 224, 368
local SPOT_X, SPOT_Y = 360, 372  -- ~136px in front on the same floor

-- Per-step position hold: keeps the bomber on its perch without
-- touching its timers.
local function hold_bomber(g, e, x, y)
  e.x, e.y, e.vx, e.vy = x, y, 0, 0
end

-- Warm-up: pins both bodies a few steps so the sight picture is stable.
local function settle(env, g, e, x, y, n, px, py)
  for _ = 1, n or 8 do
    env.love.update(1/30)
    env.love.draw()
    hold_bomber(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
  end
end

-- Runs steps until the telegraph throws a bomb (then one more, so the
-- bomb's first full flight tick has processed). Pins both bodies every
-- step. Returns the live bomb plus a snapshot taken the moment it was
-- first seen (one flight tick in -- the flight is uniform, so velocity
-- and the fuse-1 read are exact), or nil if nothing was thrown.
local function fire_first_bomb(env, g, e, x, y, px, py)
  for _ = 1, math.ceil(config.enemies.bomber_aim_steps) + 4 do
    env.love.update(1/30)
    env.love.draw()
    hold_bomber(g, e, x, y)
    place_player(g, px or SPOT_X, py or SPOT_Y)
    if #g.ctx.ents.bombs > 0 then
      local b = g.ctx.ents.bombs[1]
      local snap = { x = b.x, y = b.y, vx = b.vx, vy = b.vy, fuse = b.fuse }
      env.love.update(1/30)
      env.love.draw()
      hold_bomber(g, e, x, y)
      place_player(g, px or SPOT_X, py or SPOT_Y)
      return b, snap
    end
  end
  return nil
end

-- ==== 1. spotting enters the aim state ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 2)
  assert_true(e.state == "aim", "the bomber aims once the player is spotted")
  assert_true(e.aim_t ~= nil and e.aim_t > 0
    and e.aim_t <= config.enemies.bomber_aim_steps,
    "the aim has a blink-telegraph timer")
  assert_true(e.last_known ~= nil, "the aim tracks the player's position")
  assert_true(e.facing == 1, "the bomber faces its aim")
  assert_true(#g.ctx.ents.bombs == 0,
    "nothing is thrown while the telegraph still blinks")
end

-- ==== 2. the telegraph throws a straight-line bomb ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 3)
  assert_true(e.state == "aim", "the bomber is mid-telegraph")
  local b, snap = fire_first_bomb(env, g, e, FLOOR_X, FLOOR_Y)
  assert_true(b ~= nil, "the blink-aim ends in a thrown bomb")
  assert_true(b.active, "the bomb is live")
  -- the throw leaves from just above the head (first sight carries one
  -- flight tick of drift)
  local step = config.enemies.bomb_speed
  assert_true(math.abs(snap.x - (FLOOR_X + 6)) <= step + 2
    and math.abs(snap.y - (FLOOR_Y - 4)) <= step + 2,
    "the bomb is thrown from just above the head ("
    .. string.format("%.1f, %.1f", snap.x, snap.y) .. ")")
  -- the flight is a straight line at the tracked spot, at bomb_speed
  local spd = math.sqrt(snap.vx*snap.vx + snap.vy*snap.vy)
  assert_true(math.abs(spd - step) < 0.01,
    "the bomb flies at bomb_speed (" .. string.format("%.2f", spd) .. ")")
  local known = e.last_known
  local mx, my = FLOOR_X + 6, FLOOR_Y - 4
  local dx, dy = known.x - mx, known.y - my
  local dist = math.sqrt(dx*dx + dy*dy)
  local dot = (snap.vx*dx + snap.vy*dy) / (spd * dist)
  assert_true(dot > 0.99, "the throw aims at the tracked spot (dot "
    .. string.format("%.3f", dot) .. ")")
  -- the fuse is the cheap estimate: floored flight time, jittered (one
  -- flight tick had already burned before first sight)
  local est = math.floor(dist / step)
  local err = config.enemies.bomb_fuse_error
  assert_true(snap.fuse >= est - err and snap.fuse <= est + err,
    "the fuse is the rough estimate jittered (fuse " .. snap.fuse
    .. ", est " .. est .. "±" .. err .. ")")
  assert_true(e.state == "wait", "the bomber waits for its cadence after throwing")
  assert_true(e.shoot_cd > 0, "throwing starts the shoot cooldown")
end

-- ==== 3. grenade: the burst lands on the throw-time spot; a dodging
--         player is unharmed ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 3)
  local target = { x = SPOT_X + 4, y = SPOT_Y + 6 }  -- the pinned centre
  -- the player dodges behind the east wall mid-telegraph: the throw
  -- fires anyway at the last known spot
  local threw, boomed, first_bomb = false, false, nil
  for _ = 1, math.ceil(config.enemies.bomber_aim_steps)
    + config.enemies.bomber_rapid_min + config.enemies.bomber_burst_count
    * (config.enemies.bomber_burst_min + config.enemies.bomber_burst_extra
      + config.enemies.bomber_aim_steps)
    + config.enemies.bomb_fuse_error + 20 do
    env.love.update(1/30)
    env.love.draw()
    hold_bomber(g, e, FLOOR_X, FLOOR_Y)
    if e.state == "aim" and e.aim_t and e.aim_t <= 2 then
      place_player(g, 768, 208)  -- fled out of sight to the spawn
    else
      place_player(g, 768, 208)
    end
    if #g.ctx.ents.bombs > 0 then
      threw = true
      if not first_bomb then first_bomb = g.ctx.ents.bombs[1] end
    end
    if #g.ctx.ents.booms > 0 then boomed = true break end
  end
  assert_true(threw, "the telegraph threw despite the player hiding")
  assert_true(boomed, "the bomb bursts on its fuse")
  local spent = true
  for _, b in ipairs(g.ctx.ents.bombs) do
    if b == first_bomb then spent = false end
  end
  assert_true(spent, "the burst bomb is gone")
  -- the burst lands near the throw-time spot (the crude fuse estimate:
  -- within the jitter's reach, not on the dot)
  local bo = g.ctx.ents.booms[1]
  local bd = math.sqrt((bo.x - target.x)^2 + (bo.y - target.y)^2)
  assert_true(bd <= config.enemies.bomb_fuse_error
    * config.enemies.bomb_speed + config.enemies.bomb_blast_radius + 4,
    "the burst lands near the throw-time spot (" .. string.format("%.1f", bd)
    .. "px)")
  -- the dodge wins: nobody home at the burst point
  local p = g.ctx.player
  assert_true(p.hp == config.player.hearts * 2,
    "the grounded player who dodged is unharmed (hp " .. p.hp .. ")")
end

-- ==== 4. flak: an airborne player is proximity-burst early ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  clear_enemies(g)
  local max_hp = config.player.hearts * 2
  -- hover the player mid-corridor (re-placed every step, so the fall
  -- never reaches the floor and gr stays false); the flight band is
  -- free air: below the floating block (y 304..319) and above the floor
  local function hover()
    place_player(g, 360, 348)
  end
  hover()
  env.love.update(1/30)
  env.love.draw()
  hover()
  local p = g.ctx.player
  assert_true(not p.gr, "the player is airborne (hovering)")
  -- a bomb flying straight through their live centre, fuse far from done
  local cx, cy = p.x + p.w/2, p.y + p.h/2
  local step = config.enemies.bomb_speed
  local Bombs = env.require("src.bombs")
  local b = Bombs.spawn(g.ctx, cx - 30, cy, step, 0, 60)
  assert_true(b ~= nil, "the bomb spawns in open air")
  local boomed = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    hover()
    if #g.ctx.ents.booms > 0 then boomed = true break end
  end
  assert_true(boomed, "the flak proximity bursts the bomb mid-flight")
  assert_true(#g.ctx.ents.bombs == 0, "the burst bomb is gone")
  local bo = g.ctx.ents.booms[1]
  local bd = math.sqrt((bo.x - cx)^2 + (bo.y - cy)^2)
  assert_true(bd <= config.enemies.bomb_flak_proximity + 4,
    "the air-burst pops within flak range of the player ("
    .. string.format("%.1f", bd) .. "px)")
  assert_true(p.hp == max_hp - config.enemies.bomb_half_hearts,
    "the air-burst costs a full heart (hp " .. p.hp .. ")")
  assert_true(p.invuln > 0, "the hit grants i-frames")
end

-- ==== 5. a grounded player is never proximity-burst ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  clear_enemies(g)
  local max_hp = config.player.hearts * 2
  -- stand the player on the corridor floor: placed at the resting top
  -- (floor surface 384, body 12 tall), physics keeps them grounded
  local function stand()
    place_player(g, 360, 372)
  end
  stand()
  env.love.update(1/30)
  env.love.draw()
  stand()
  local p = g.ctx.player
  assert_true(p.gr, "the player is standing on the floor")
  -- a bomb flying straight through their box with a long fuse: the
  -- grenade must not proximity-burst a grounded target
  local cx, cy = p.x + p.w/2, p.y + p.h/2
  local step = config.enemies.bomb_speed
  local Bombs = env.require("src.bombs")
  local b = Bombs.spawn(g.ctx, cx - 30, cy, step, 0, 100)
  local passed = false
  for _ = 1, 14 do
    env.love.update(1/30)
    env.love.draw()
    stand()
    if b.x >= cx then passed = true break end
  end
  assert_true(passed, "the bomb flies through the player's box")
  assert_true(#g.ctx.ents.booms == 0,
    "no proximity burst over a grounded player")
  assert_true(p.hp == max_hp, "flying through a grounded player hurts nobody")
end

-- ==== 6. terrain bounces the grenade body, the fuse still pops ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local max_hp = config.player.hearts * 2
  -- a bomb flying east at the corridor's east wall (face x=384), fuse
  -- far from done: it bounces back, damped, and bursts later
  local Bombs = env.require("src.bombs")
  local b = Bombs.spawn(g.ctx, 340, 376, config.enemies.bomb_speed, 0, 100)
  local pre_vx = b.vx
  local bounced = false
  for _ = 1, 40 do
    env.love.update(1/30)
    env.love.draw()
    if not b.active then break end
    if b.vx < 0 and pre_vx > 0 then bounced = true break end
  end
  assert_true(bounced, "the wall bounces the grenade body back")
  assert_true(math.abs(b.vx - -pre_vx * config.enemies.bomb_bounce_damp) < 0.01,
    "the bounce reflects and damps (vx " .. string.format("%.2f", b.vx) .. ")")
  assert_true(b.active and #g.ctx.ents.booms == 0,
    "terrain contact detonates nothing")
  -- the fuse still burns: the burst comes later, far from the player
  local popped = false
  for _ = 1, math.ceil(config.enemies.bomb_speed * 100 / 3.5) do
    env.love.update(1/30)
    env.love.draw()
    if #g.ctx.ents.booms > 0 then popped = true break end
  end
  assert_true(popped, "the resting bomb bursts on its fuse")
  assert_true(g.ctx.player.hp == max_hp, "the far player is unharmed")
end

-- ==== 7. an arrow tip detonates a bomb; the blast kills enemies ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  place_player(g, 540, 212)
  settle(env, g, e, FLOOR_X, FLOOR_Y, 2)
  local max_hp = config.player.hearts * 2
  -- a bomb in open air with a dummy enemy right beside it
  local cfg = config.enemies
  local Bombs = env.require("src.bombs")
  Bombs.spawn(g.ctx, 446, 150, 0.5, 0, 100)
  local dummy = {
    x = 440, y = 156, home_x = 440,
    vx = 0, vy = 0, w = cfg.width, h = cfg.height,
    gr = false, facing = 1, type = "melee",
    shoot_cd = 0, spr = 105, rot = nil,
    state = "patrol", last_known = nil,
  }
  table.insert(g.ctx.ents.enemies, dummy)
  -- a player arrow arriving at the bomb's position from the left
  table.insert(g.ctx.ents.arrows, {
    x = 446, y = 150, vx = 2, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 100,
    kind = "normal", traveled = 0,
  })
  env.love.update(1/30)
  env.love.draw()
  assert_true(#g.ctx.ents.bombs == 0, "the arrow tip detonates the bomb")
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

-- ==== 8. bombs come in bursts of burst_count per charge ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true  -- keep the pinned player alive all loop
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  -- count throws exactly: wrap the shared module's spawn
  local Bombs = env.require("src.bombs")
  local real_spawn = Bombs.spawn
  local throws, charges = 0, 0
  Bombs.spawn = function(ctx, x, y, vx, vy, fuse)
    local b = real_spawn(ctx, x, y, vx, vy, fuse)
    if b then throws = throws + 1 end
    return b
  end
  local waits = {}
  local last_state = e.state
  for _ = 1, 700 do
    env.love.update(1/30)
    env.love.draw()
    hold_bomber(g, e, FLOOR_X, FLOOR_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.state == "wait" and last_state ~= "wait" then
      waits[#waits + 1] = e.wait_t
      if e.wait_t >= config.enemies.bomber_rapid_min then
        -- the long recharge closes a charge: it must have held exactly
        -- the burst budget's worth of throws
        throws = throws -- luacheck: ignore (read below)
        local charge_throws = throws
        throws = 0
        charges = charges + 1
        assert_true(charge_throws == config.enemies.bomber_burst_count,
          "each charge throws " .. config.enemies.bomber_burst_count
          .. " bombs (charge " .. charges .. " held " .. charge_throws .. ")")
      end
    end
    last_state = e.state
  end
  assert_true(charges >= 2,
    "the bomber recharges into further bursts (" .. charges .. " charges)")
  for _, wt in ipairs(waits) do
    local burst = wt >= config.enemies.bomber_burst_min
      and wt <= config.enemies.bomber_burst_min + config.enemies.bomber_burst_extra
    local long = wt >= config.enemies.bomber_rapid_min
      and wt <= config.enemies.bomber_rapid_min + config.enemies.bomber_rapid_extra
    assert_true(burst or long,
      "each follow-up wait is either a burst gap or the full recharge ("
      .. wt .. ")")
  end
  -- burst throws must also track: the tracked spot matches the pinned
  -- player at every telegraph
  assert_true(e.last_known ~= nil
    and math.abs(e.last_known.x - (SPOT_X + 4)) < 2,
    "the burst throws keep tracking the player's live position")
end

-- ==== 9. the airborne cap drops excess throws ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  local cfg = config.enemies
  local Enemies = env.require("src.enemies")
  for _ = 1, cfg.bomb_max_alive do
    table.insert(g.ctx.ents.bombs, {
      x = FLOOR_X + 6, y = 300,
      vx = 1, vy = 0,
      active = true, fuse = cfg.bomber_rapid_min,
    })
  end
  Enemies.fire_bomb(g.ctx, e)
  assert_true(#g.ctx.ents.bombs == cfg.bomb_max_alive,
    "the cap blocks throws beyond bomb_max_alive")
  table.remove(g.ctx.ents.bombs)
  Enemies.fire_bomb(g.ctx, e)
  assert_true(#g.ctx.ents.bombs == cfg.bomb_max_alive,
    "a freed slot accepts the next throw")
end

-- ==== 10. the enemies toggle disarms a firing bomber ====
do
  local env = fresh_game()
  local g = env.TWANG_TEST.game
  g.settings.invincible = true
  local e = make_bomber(g, FLOOR_X, FLOOR_Y)
  drop_other_enemies(g, e)
  e.facing = 1
  place_player(g, SPOT_X, SPOT_Y)
  settle(env, g, e, FLOOR_X, FLOOR_Y)
  assert_true(fire_first_bomb(env, g, e, FLOOR_X, FLOOR_Y) ~= nil,
    "the bomber aimed and threw before the toggle")

  g:toggle_enemies()
  assert_true(not g.ctx.config.enemies.enabled, "the toggle turns the enemies off")
  assert_true(#g.ctx.ents.bombs == 0, "bombs in flight are cleared")
  assert_true(e.state == "patrol",
    "a mid-shot bomber drops back to patrol")
  local frozen_x = e.x
  for _ = 1, 30 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(e.x == frozen_x and #g.ctx.ents.bombs == 0,
    "disabled bombers stay frozen and throw nothing")

  g:toggle_enemies()
  assert_true(g.ctx.config.enemies.enabled, "the toggle turns the enemies back on")
  e.shoot_cd = 0  -- the frozen cooldown would outlast this check
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
    hold_bomber(g, e, FLOOR_X, FLOOR_Y)
    place_player(g, SPOT_X, SPOT_Y)
    if e.state == "aim" then break end
  end
  assert_true(e.state == "aim", "bombers resume hunting after re-enabling")
end

print(("bomber tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
