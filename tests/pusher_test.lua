-- Pusher tests (deterministic, headless; requires LuaJIT).
--
-- Covers the pusher puzzle device (level1's pusher_01 object: a solid
-- one-tile block at tile (89, 14), struck by player arrows):
--   1. the entity scans from the Tiled object (tile-owned, grouped)
--   2. its tile is a solid block to bodies but recessed to arrows
--   3. an arrow striking it is consumed (poof) and the device fires:
--      the shared flash ring and a player directly above launched
--      straight up at full push strength (additive)
--   4. the shove is radial: a player beside the device is thrown away
--      from it; a player beyond the catch radius is untouched
--   5. the push knocks a carried rope line loose and rides the grace
--      window (the walk cap cannot clamp the launch)
--   6. repeatable: a second strike fires the push again
--   7. enemies in range are shoved along the radial and never killed
--   8. a bomb arrow striking it detonates its own blast AND fires the
--      pusher (two flashes, the shoves stack)
--
-- Usage (from the project root): luajit tests/pusher_test.lua

local Harness = dofile("tests/harness.lua")
local config = require("src.config")

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

-- Rigs a player arrow mid-flight one step from the pusher's tile.
local function rig_arrow(g, kind, vx, vy)
  local pu = g.ctx.ents.pushers[1]
  local a = {
    x = pu.x + 8 - vx, y = pu.y + 8 - vy,
    vx = vx, vy = vy,
    active = true, stuck = false, bounced = 0,
    sdx = 0, sdy = 1, spin = 0, lt = 300,
    kind = kind or "normal", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

-- ==== 1. the entity scans from the level ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local pu = g.ctx.ents.pushers[1]
  assert_true(pu ~= nil, "pusher_01 scans into ents.pushers")
  assert_true(pu.tc == 89 and pu.tr == 14,
    "the pusher owns tile (89, 14) (got "
    .. tostring(pu and pu.tc) .. ", " .. tostring(pu and pu.tr) .. ")")
  assert_true(pu.g == "01", "pusher_01 resolves its group from the name")
  assert_true(pu.spr == 86, "the pusher draws its placed sprite (86)")
  local w = g.ctx.world
  assert_true(w:solid_at(pu.x + 8, pu.y + 8),
    "the pusher's tile is a solid block to bodies")
  assert_true(not w:solid_for_arrow(pu.x + 8, pu.y + 8),
    "the pusher's tile is recessed to arrows (they fly in and strike)")
end

-- Runs steps until the rigged arrow is consumed (or the cap trips).
local function run_until_consumed(env, a, cap)
  local steps = 0
  while a.active and steps < cap do
    run_steps(env, 1)
    steps = steps + 1
  end
  return steps
end

-- ==== 2. the strike: arrow consumed, flash fired, the player above launched ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, ctx.ents.pushers[1]
  -- standing directly above the device (its tile top is the launch pad)
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  assert_true(p.gr, "the player lands on the pusher to set up the launch")
  local a = rig_arrow(g, "normal", 0, 6)
  local steps = run_until_consumed(env, a, 5)
  assert_true(steps > 0 and steps <= 5, "the arrow reaches the device")
  assert_true(not a.active, "the striking arrow is consumed by the device")
  assert_true(#ctx.ents.booms > 0, "the strike fires the shared flash ring")
  assert_true(p.vy == -config.pusher.push,
    "the player above is launched straight up at full push (vy " .. p.vy .. ")")
  assert_true(not p.gr, "the launch leaves the ground")
  assert_true(p.winch_grace ~= nil and p.winch_grace > 0,
    "the launch rides the shove grace window")
end

-- ==== 3. the shove is radial and range-capped ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, ctx.ents.pushers[1]
  -- a player to the device's LEFT on the same floor line: shoved leftward
  p.x, p.y, p.vx, p.vy = pu.x - 12, pu.y - 1, 0, 0
  run_steps(env, 2)
  rig_arrow(g, "normal", 6, 0)  -- an arrow flying right into the device
  run_steps(env, 2)
  assert_true(p.vx < 0, "a player beside the device is shoved away (vx "
    .. p.vx .. ")")
  -- a player well beyond the 4-tile catch radius is untouched
  local env2 = Harness.boot()
  local g2 = env2.TWANG_TEST.game
  local p2, pu2 = g2.ctx.player, g2.ctx.ents.pushers[1]
  p2.x, p2.y, p2.vx, p2.vy = pu2.x + config.pusher.radius + 24, pu2.y, 0, 0
  rig_arrow(g2, "normal", 6, 0)
  run_steps(env2, 3)
  assert_true(p2.vx == 0 and p2.vy == 0,
    "a player beyond the catch radius feels nothing")
end

-- ==== 4. the launch knocks a rope loose and ignores the walk cap ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, ctx.ents.pushers[1]
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  -- fake an attached rope (anchored in the floor below the device, so
  -- the rope survives the pre-strike rope pass) that the strike can knock
  -- loose: the tip sits inside the solid floor tile, pointing deeper
  p.rope = { arrow = { active = true, stuck = true,
    x = pu.x + 8, y = pu.y + 24, sdx = 0, sdy = 1 }, length = 40 }
  local a = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a, 5)
  assert_true(p.rope == nil, "the shove knocks an attached rope loose")
  -- a horizontal launch would be clamped by the walk cap; the grace
  -- keeps it playing out untouched until it lapses or the player lands
  assert_true(p.winch_grace ~= nil,
    "the launch carries a grace window (winch_grace set)")
end

-- ==== 5. repeatable: the second strike fires the push again ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, ctx.ents.pushers[1]
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  local a = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a, 5)
  assert_true(p.vy == -config.pusher.push, "the first strike launches")
  -- let the grace lapse and return the player to the pad (they flew
  -- out of the catch radius during the first launch)
  run_steps(env, config.pusher.shove_grace)
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  local a2 = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a2, 5)
  assert_true(not a2.active, "the second strike consumes its arrow too")
  -- the knock is additive (the player already carries the fall speed
  -- gained while being re-placed), so allow one gravity step of drift
  assert_true(p.vy < -(config.pusher.push - 1),
    "the device is repeatable: the second strike launches again (vy "
    .. p.vy .. ")")
end

-- ==== 6. enemies are shoved, never killed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local pu = ctx.ents.pushers[1]
  local e = { x = pu.x + 8 - 30, y = pu.y + 8 - 8, w = 12, h = 16,
    vx = 0, vy = 0, gr = false, facing = 1, type = "melee",
    shoot_cd = 90, state = "patrol" }
  table.insert(ctx.ents.enemies, e)
  local count = #ctx.ents.enemies
  local a = rig_arrow(g, "normal", 6, 0)
  run_until_consumed(env, a, 5)
  assert_true(e.vx < 0, "an enemy in range is shoved along the radial (vx "
    .. e.vx .. ")")
  assert_true(#ctx.ents.enemies == count,
    "the shove never kills: the enemy is still standing")
end

-- ==== 7. a bomb arrow stacks its blast with the push ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, ctx.ents.pushers[1]
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  local a = rig_arrow(g, "bomb", 0, 6)
  run_until_consumed(env, a, 5)
  assert_true(not a.active, "the bomb arrow is consumed at the strike")
  -- the bomb's blast flash AND the pusher's flash: two booms spawned
  local booms = #ctx.ents.booms
  assert_true(booms >= 2,
    "the bomb blast and the pusher's push both fire (booms "
    .. booms .. " live)")
  assert_true(p.vy < -config.pusher.push,
    "the two shoves stack for a bigger launch (vy " .. p.vy .. ")")
end

print("pusher tests: " .. PASS .. " passed, " .. FAIL .. " failed")
if FAIL > 0 then os.exit(1) end
