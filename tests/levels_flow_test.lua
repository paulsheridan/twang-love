-- Generated-level gameplay tests (deterministic, headless; LuaJIT).
--
-- Exercises the v1 ladder's core puzzles on the real maps:
--   1. meadow: key pickup -> lock -> door opens; the exit completes
--   2. battlements: an arrow striking the switch opens its door
--   3. crossing: the rigged rope swing lands the player on the far ledge
--      (the swing geometry the level's chasm is built around)
--   4. springside: a switch strike vaults a player standing on the
--      spring; the phase switch dissolves the phase wall
--
-- Usage (from the project root): luajit tests/levels_flow_test.lua

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

local tw = config.tile_size

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

local function load(env, path)
  local g = env.TWANG_TEST.game
  g:load_level(path)
  g.mode = "play"
  step(env)
  return g
end

-- ==== 1. meadow: the key/lock/door chain and the exit ====
do
  local env = Harness.boot()
  local g = load(env, "maps/meadow.json")
  local p, ents = g.ctx.player, g.ctx.ents
  assert_true(#ents.keys == 3 and #ents.locks == 2 and #ents.doors == 4,
    "the meadow carries two key/lock puzzles and two 2-tall doors")
  -- walk into the ground key: pickup
  local ground_key
  for _, k in ipairs(ents.keys) do
    if not k.taken and k.y == 15 * tw then ground_key = k end
  end
  assert_true(ground_key ~= nil, "a key sits on the ground")
  p.x, p.y, p.vx, p.vy = ground_key.x, ground_key.y + 4, 0, 0
  for _ = 1, 6 do step(env) end
  assert_true(p.key == ground_key, "walking into the key picks it up")
  -- carry it to the lock: the door opens
  local lock
  for _, l in ipairs(ents.locks) do if l.g == ground_key.g then lock = l end end
  p.x, p.y, p.vx, p.vy = lock.x, lock.y + 4, 0, 0
  for _ = 1, 6 do step(env) end
  assert_true(lock.triggered, "the lock triggers")
  local door_open = true
  for _, d in ipairs(ents.doors) do
    if d.g == ground_key.g and not d.open then door_open = false end
  end
  assert_true(door_open, "the group's doors open")
  -- the key was consumed at the lock: the exit completes the level
  p.key = nil
  local exit
  for _, e in ipairs(ents.exits) do exit = e end
  p.x, p.y, p.vx, p.vy = exit.x, exit.y, 0, 0
  step(env)
  assert_true(g.mode == "complete", "touching the exit clears the meadow")
end

-- ==== 2. battlements: an arrow strike opens the switch gate ====
do
  local env = Harness.boot()
  local g = load(env, "maps/battlements.json")
  local ents = g.ctx.ents
  local door
  for _, d in ipairs(ents.doors) do door = d end
  assert_true(door ~= nil and not door.open, "the gate starts closed")
  -- rig an arrow flying into the switch's tile (as a player's lofted
  -- shot would)
  local sw
  for _, s in ipairs(ents.switches) do sw = s end
  local a = {
    x = sw.x - 4, y = sw.y + 8, vx = 13, vy = -2,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal", traveled = 4,
  }
  table.insert(ents.arrows, a)
  local struck = false
  for _ = 1, 30 do
    step(env)
    if sw.on then struck = true break end
  end
  assert_true(struck, "the arrow flips the switch")
  assert_true(door.open, "the switch gate stands open")
end

-- ==== 3. crossing: the rigged swing lands on the far ledge ====
do
  local env = Harness.boot()
  local g = load(env, "maps/crossing.json")
  local p, keys = g.ctx.player, env.TWANG_TEST.keys_down
  p.x, p.y, p.vx, p.vy = 448, 116, 0, 0
  for _ = 1, 30 do step(env) if p.gr then break end end
  local a = {
    x = 538, y = 70, vx = 0, vy = -2,
    active = true, stuck = true, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 30000,
    kind = "rope", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  step(env)
  assert_true(p.rope ~= nil, "the swing attaches")
  -- pump right; release when high on the forward arc
  local released = false
  for _ = 1, 200 do
    keys.right = true
    step(env)
    keys.right = nil
    step(env)
    if p.x > 545 and p.vx > 1 and p.y < 160 then
      env.love.keypressed("x")
      step(env)
      released = true
      break
    end
  end
  assert_true(released, "the pump reaches the release window")
  local landed = false
  for _ = 1, 120 do
    step(env)
    if p.gr then landed = true break end
  end
  assert_true(landed, "the released player lands")
  assert_true(p.x >= 576 and p.y <= 240,
    "the swing carries the player onto the far ledge")
end

-- ==== 4. springside: spring vault + phase dissolve ====
do
  local env = Harness.boot()
  local g = load(env, "maps/springside.json")
  local p, ents, world = g.ctx.player, g.ctx.ents, g.ctx.world
  assert_true(world.phase_solid, "phase tiles start solid")
  -- stand on the intro spring; the switch strike vaults the player
  local spring
  for _, s in ipairs(ents.springs) do
    if s.g == "01" then spring = s end
  end
  assert_true(spring ~= nil, "the intro spring exists")
  p.x, p.y, p.vx, p.vy = spring.x, spring.y + tw - 8 - 12, 0, 0
  for _ = 1, 6 do step(env) end
  assert_true(p.gr, "the player stands on the spring's pad")
  local top = p.y
  -- rig the strike (as the player's arrow shot would)
  local sw
  for _, s in ipairs(ents.switches) do if s.g == "01" then sw = s end end
  local a = {
    x = sw.x - 4, y = sw.y + 8, vx = 13, vy = -2,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal", traveled = 4,
  }
  table.insert(ents.arrows, a)
  local vaulted = false
  for _ = 1, 30 do
    step(env)
    if p.vy < -6 then vaulted = true break end
  end
  assert_true(vaulted, "the switch strike vaults the player off the pad")
  -- the phase switch: rig a strike; the phase wall dissolves
  local phase_switch
  for _, s in ipairs(ents.switches) do if s.phase then phase_switch = s end end
  assert_true(phase_switch ~= nil, "the phase switch exists")
  local b = {
    x = phase_switch.x - 4, y = phase_switch.y + 8, vx = 13, vy = -2,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal", traveled = 4,
  }
  table.insert(ents.arrows, b)
  local flipped = false
  for _ = 1, 30 do
    step(env)
    if not world.phase_solid then flipped = true break end
  end
  assert_true(flipped, "the phase switch dissolves the phase tiles")
  -- the phase wall's cells no longer block
  assert_true(not world:solid_at(24 * tw + 8, 21 * tw + 8),
    "the phase wall's corridor cell is passable")
end

-- ==== 5. arrowslit: the slit hides from sight, passes arrows ====
do
  local env = Harness.boot()
  local g = load(env, "maps/arrowslit.json")
  local p, ents, world = g.ctx.player, g.ctx.ents, g.ctx.world
  -- stand just left of the first slit wall (x=42, slit at row 15)
  p.x, p.y, p.vx, p.vy = 40 * tw, 14 * tw, 0, 0
  for _ = 1, 10 do step(env) end
  local laser
  for _, e in ipairs(ents.enemies) do
    if e.type == "laser" and e.x > 42 * tw then laser = e break end
  end
  assert_true(laser ~= nil, "a laser patrols beyond the slit wall")
  -- the laser cannot see the player behind the slit wall
  assert_true(not env.require("src.enemies").sees(g.ctx, laser),
    "the slit wall blocks the laser's sight")
  -- an arrow through the slit reaches the ground beyond
  local a = {
    x = 40 * tw + 8, y = 15 * tw + 6, vx = 13, vy = -2,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal", traveled = 4,
  }
  table.insert(ents.arrows, a)
  local killed = false
  for _ = 1, 30 do
    step(env)
    if not a.active then killed = true break end
  end
  assert_true(killed, "the arrow flies through the slit")
  assert_true(laser.hp == nil, true)  -- lasers die by removal; check via list
  local laser_alive = false
  for _, e in ipairs(ents.enemies) do
    if e == laser then laser_alive = true end
  end
  assert_true(not laser_alive,
    "the shot through the slit kills the laser beyond")
end

-- ==== 6. winchyard: a rope arrow into the winch zips the player ====
do
  local env = Harness.boot()
  local g = load(env, "maps/winchyard.json")
  local p, ents = g.ctx.player, g.ctx.ents
  assert_true(#ents.winches == 3, "the winchyard carries three winches")
  -- stand at the first void's left edge (the void spans cols 12..19)
  p.x, p.y, p.vx, p.vy = 11 * tw, 17 * tw, 0, 0
  for _ = 1, 10 do step(env) end
  local edge_x = p.x
  -- rig a rope arrow flying into the first winch's box (as the player's
  -- up-shot would); the capture reels and throws them across the void
  local winch = ents.winches[1]
  local a = {
    x = winch.x - 10, y = winch.y + tw/2, vx = 8, vy = -3,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = -1, spin = 0, lt = 300, kind = "rope", traveled = 4,
  }
  table.insert(ents.arrows, a)
  local captured = false
  for _ = 1, 20 do
    step(env)
    if p.winch then captured = true break end
  end
  assert_true(captured, "the rope arrow is captured by the winch")
  -- ride the reel and the throw: the player must land past the void
  -- (the void spans x=192..320; the far ledge starts at col 20)
  local landed = false
  for _ = 1, 160 do
    step(env)
    if p.gr then landed = true break end
  end
  assert_true(landed, "the thrown player lands")
  assert_true(p.x >= 18 * tw,
    "the winch throw carries the player across the void")
end

-- ==== 7. the vault: the bomb ride grabs the floating key ====
do
  local env = Harness.boot()
  local g = load(env, "maps/vault.json")
  local p, ents = g.ctx.player, g.ctx.ents
  local shelf_key
  for _, k in ipairs(ents.keys) do
    if k.g == "02" then shelf_key = k end
  end
  assert_true(shelf_key ~= nil, "the floating key exists")
  -- stand under it, fire a bomb at the floor, ride up through the key
  p.x, p.y, p.vx, p.vy = 26 * tw, 15 * tw, 0, 0
  for _ = 1, 10 do step(env) end
  p.arrow_kind = "bomb"
  local Arrows = env.require("src.arrows")
  Arrows.fire(g.ctx, 0.25, "bomb", 1.0)  -- straight down (p8 0.25 = down)
  local a = ents.arrows[1]
  assert_true(a ~= nil and a.kind == "bomb", "the bomb arrow fires")
  local grabbed = false
  for _ = 1, 60 do
    step(env)
    if p.key == shelf_key then grabbed = true break end
  end
  assert_true(grabbed, "the blast ride carries the player through the key")
  assert_true(p.hp == config.player.hearts * 2,
    "the ride costs no health")
end

print(("levels flow tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
