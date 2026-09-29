-- Pusher tests (deterministic, headless; requires LuaJIT).
--
-- Covers the pusher puzzle device family (level1's pusher_01 objects:
-- solid one-tile blocks, struck by player arrows; the strike site is
-- tile (89, 14) in the area the test device sits in):
--
--   1. the entities scan from the Tiled objects (Class Updraft /
--      Outdraft resolve the kind; tile (89, 14) is the outdraft device
--      the other tests rig)
--   2. the device's tile is a solid block to bodies but recessed to
--      arrows
--   3. an arrow striking it is consumed (poof) and the device fires:
--      the shared flash ring and a player inside its catch zone
--      launched at full push strength (additive)
--   4. the updraft is a column drag: a player overlapping the device's
--      column or up to 2 tiles to either side, between the device's
--      top edge and 4 tiles above it, launches straight up; a player
--      3 tiles to the side or below the device's top edge is untouched
--   5. the outdraft is a sector drain: a player within the 45-degree
--      cone above the device is shoved along the radial (up-and-away);
--      a player at a steeper angle or below the device is untouched
--   6. the push knocks a carried rope line loose and rides the grace
--      window (the walk cap cannot clamp the launch)
--   7. repeatable: a second strike fires the push again
--   8. enemies in range are shoved along the flow and never killed
--   9. a bomb arrow striking it detonates its own blast AND fires the
--      device (two flashes, the shoves stack)
--  10. a plain strike fires the device's flash ring without shaking
--      the camera
--
-- Usage (from the project root): luajit tests/pusher_test.lua

local Harness = dofile("tests/harness.lua")
local config = require("src.config")
local Arrows = require("src.arrows")

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

-- Rigs a player arrow mid-flight one step from the device's tile.
local function rig_arrow(g, kind, vx, vy)
  local pu = g.ctx.ents.pushers[1]
  local art = g.ctx.config.art_size
  local a = {
    x = pu.x + art/2 - vx, y = pu.y + art/2 - vy,
    vx = vx, vy = vy,
    active = true, stuck = false, bounced = 0,
    sdx = 0, sdy = 1, spin = 0, lt = 300,
    kind = kind or "normal", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

-- ==== 1. the entities scan from the level ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local pus = g.ctx.ents.pushers
  assert_true(#pus == 4, "level1 scans all four pusher-family objects (got "
    .. tostring(#pus) .. ")")
  local by_tile = {}
  for _, pu in ipairs(pus) do
    by_tile[pu.tc .. "," .. pu.tr] = pu
  end
  local pu = by_tile["178,28"]
  assert_true(pu ~= nil, "the test device scans at sub-tile (178, 28)")
  assert_true(pu.variant == "outdraft",
    "the Class Outdraft object resolves the outdraft variant (got "
    .. tostring(pu and pu.variant) .. ")")
  assert_true(pu.g == "01", "pusher_01 resolves its group from the name")
  assert_true(pu.spr == 86, "the pusher draws its placed sprite (86)")
  local n_updraft = 0
  local n_outdraft = 0
  for _, pu2 in ipairs(pus) do
    if pu2.variant == "updraft" then n_updraft = n_updraft + 1 end
    if pu2.variant == "outdraft" then n_outdraft = n_outdraft + 1 end
  end
  assert_true(n_updraft == 2, "two Updraft objects scan in (got "
    .. n_updraft .. ")")
  assert_true(n_outdraft == 2, "two Outdraft objects scan in (got "
    .. n_outdraft .. ")")
  local w = g.ctx.world
  assert_true(w:solid_at(pu.x + 8, pu.y + 8),
    "the pusher's tile is a solid block to bodies")
  assert_true(not w:solid_for_arrow(pu.x + 8, pu.y + 8),
    "the pusher's tile is recessed to arrows (they fly in and strike)")
end

-- The device these tests rig: the outdraft at tile (89, 14).
local function test_device(g)
  for _, pu in ipairs(g.ctx.ents.pushers) do
    if pu.tc == 178 and pu.tr == 28 then return pu end
  end
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
-- (the cone's centre line: straight above the device, launched at full
-- push; the vy is exactly -push from a still start at the pad's top)
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, test_device(g)
  -- standing directly above the device (its tile top is the launch pad)
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  assert_true(p.gr, "the player lands on the pusher to set up the launch")
  local a = rig_arrow(g, "normal", 0, 6)
  local steps = run_until_consumed(env, a, 5)
  assert_true(steps > 0 and steps <= 5, "the arrow reaches the device")
  assert_true(not a.active, "the striking arrow is consumed by the device")
  assert_true(#ctx.ents.booms > 0, "the strike fires the shared flash ring")
  -- the sample may catch one gravity tick after the launch
  local tick = config.physics.gravity * (30 / config.sim.rate)
  assert_true(math.abs(p.vy - (-config.pusher.push)) <= tick,
    "the player above is launched at full push (vy " .. p.vy .. ")")
  assert_true(not p.gr, "the launch leaves the ground")
  assert_true(p.winch_grace ~= nil and p.winch_grace > 0,
    "the launch rides the shove grace window")
end

-- ==== 3. the outdraft cone: inside angled = radial launch; steep or
-- below = nothing ====
--
-- A player standing up-and-sideways of the device inside the 45-degree
-- cone is thrown along the radial: both components fire, the horizontal
-- one away from the device.
--
-- Player box is 8x13, so its centre sits 4 right and 6.5 down of its
-- top-left; the device centre is (pu.x+8, pu.y+8). A centre 32 right and
-- 35 up of the device's centre is atan(32/35) = ~42.4 degrees off
-- vertical -- inside the cone.
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, test_device(g)
  p.x, p.y, p.vx, p.vy = pu.x + 36, pu.y - 42, 0, 0
  run_steps(env, 2)
  local a = rig_arrow(g, "normal", 6, 0)  -- an arrow flying right into it
  run_until_consumed(env, a, 5)
  assert_true(p.vx > 0 and p.vy < 0,
    "a player inside the cone is shoved up-and-away (vx " .. p.vx
    .. ", vy " .. p.vy .. ")")
  -- a player standing beside the device (radial near-horizontal, outside
  -- the cone) feels nothing
  local env2 = Harness.boot()
  local g2 = env2.TWANG_TEST.game
  local p2, pu2 = g2.ctx.player, test_device(g2)
  p2.x, p2.y, p2.vx, p2.vy = pu2.x - 12, pu2.y - 1, 0, 0
  run_steps(env2, 2)
  rig_arrow(g2, "normal", 6, 0)
  run_steps(env2, 3)
  assert_true(p2.vx == 0 and p2.vy == 0,
    "a player beside the device (outside the cone) feels nothing")
  -- a player below the device's centre (under it, radial pointing down)
  -- is untouched too
  local env3 = Harness.boot()
  local g3 = env3.TWANG_TEST.game
  local p3, pu3 = g3.ctx.player, test_device(g3)
  p3.x, p3.y, p3.vx, p3.vy = pu3.x + 4, pu3.y + 32, 0, 0
  run_steps(env3, 2)
  rig_arrow(g3, "normal", 6, 0)
  run_steps(env3, 3)
  assert_true(p3.vx == 0 and p3.vy == 0,
    "a player below the device feels nothing")
  -- and a player inside the cone's slice but beyond the 4-tile radius
  -- stays put
  local env4 = Harness.boot()
  local g4 = env4.TWANG_TEST.game
  local p4, pu4 = g4.ctx.player, test_device(g4)
  p4.x, p4.y, p4.vx, p4.vy = pu4.x + 100, pu4.y - 130, 0, 0
  run_steps(env4, 2)
  rig_arrow(g4, "normal", 6, 0)
  run_steps(env4, 3)
  assert_true(p4.vx == 0 and p4.vy == 0,
    "a player beyond the catch radius inside the cone feels nothing")
end

-- ==== 4. the updraft column: side-band and reach window ====
--
-- Straight rig: a pusher entity's variant drives the zone geometry, no
-- arrow needed -- fire trigger_pusher directly and read the player.
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local pu = test_device(g)
  pu.variant = "updraft"
  local p = ctx.player
  -- 2 tiles to the right of the device's column, one tile above its top:
  -- inside the side band (side = 2 tiles), launched straight up
  p.x, p.y, p.vx, p.vy = pu.x + 32 + 4, pu.y - 32, 0, 0
  Arrows.trigger_pusher(ctx, pu)
  -- the sample may catch one gravity tick after the launch
  local tick = config.physics.gravity * (30 / config.sim.rate)
  assert_true(p.vx == 0 and math.abs(p.vy - (-config.pusher.push)) <= tick,
    "the updraft catches 2 tiles to the side and launches straight up "
    .. "(vx " .. p.vx .. ", vy " .. p.vy .. ")")
  -- 3 tiles to the right: beyond the side band, untouched
  local env2 = Harness.boot()
  local g2 = env2.TWANG_TEST.game
  local ctx2, pu2, p2 = g2.ctx, test_device(g2), g2.ctx.player
  pu2.variant = "updraft"
  p2.x, p2.y, p2.vx, p2.vy = pu2.x + 48 + 4, pu2.y - 32, 0, 0
  Arrows.trigger_pusher(ctx2, pu2)
  assert_true(p2.vx == 0 and p2.vy == 0,
    "the updraft ignores a player 3 tiles to the side")
  -- inside the column but BELOW the device's top edge: untouched
  local env3 = Harness.boot()
  local g3 = env3.TWANG_TEST.game
  local ctx3, pu3, p3 = g3.ctx, test_device(g3), g3.ctx.player
  pu3.variant = "updraft"
  p3.x, p3.y, p3.vx, p3.vy = pu3.x + 4, pu3.y + 8, 0, 0
  Arrows.trigger_pusher(ctx3, pu3)
  assert_true(p3.vx == 0 and p3.vy == 0,
    "the updraft ignores a player at the device's own height or below")
  -- just above the reach cap (4 tiles up + 1): untouched
  local env4 = Harness.boot()
  local g4 = env4.TWANG_TEST.game
  local ctx4, pu4, p4 = g4.ctx, test_device(g4), g4.ctx.player
  pu4.variant = "updraft"
  p4.x, p4.y, p4.vx, p4.vy = pu4.x + 4,
    pu4.y - config.pusher.up.reach - 8, 0, 0
  Arrows.trigger_pusher(ctx4, pu4)
  assert_true(p4.vx == 0 and p4.vy == 0,
    "the updraft ignores a player beyond its reach above")
end

-- ==== 5. the launch knocks a rope loose and ignores the walk cap ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, test_device(g)
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
  -- the outdraft's angled launch would be clamped by the walk cap; the
  -- grace keeps it playing out untouched until it lapses or the player
  -- lands
  assert_true(p.winch_grace ~= nil,
    "the launch carries a grace window (winch_grace set)")
end

-- ==== 6. repeatable: the second strike fires the push again ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, test_device(g)
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  local a = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a, 5)
  -- the sample may catch one gravity tick after the launch
  local tick = config.physics.gravity * (30 / config.sim.rate)
  assert_true(math.abs(p.vy - (-config.pusher.push)) <= tick,
    "the first strike launches")
  -- let the grace lapse and return the player to the pad (they flew
  -- out of the catch zone during the first launch)
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

-- ==== 7. enemies are shoved, never killed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local pu = test_device(g)
  -- an enemy inside the cone above the device: shoved up-and-away
  local e = { x = pu.x + 4, y = pu.y - 24, w = 12, h = 16,
    vx = 0, vy = 0, gr = false, facing = 1, type = "melee",
    shoot_cd = 90, state = "patrol" }
  table.insert(ctx.ents.enemies, e)
  local count = #ctx.ents.enemies
  local a = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a, 5)
  assert_true(e.vy < 0,
    "an enemy inside the cone is shoved up-and-away (vy " .. e.vy .. ")")
  assert_true(#ctx.ents.enemies == count,
    "the shove never kills: the enemy is still standing")
end

-- ==== 8. a bomb arrow stacks its blast with the push ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local p, pu = ctx.player, test_device(g)
  p.x, p.y, p.vx, p.vy = pu.x + 4, pu.y - 13, 0, 0
  run_steps(env, 2)
  local a = rig_arrow(g, "bomb", 0, 6)
  run_until_consumed(env, a, 5)
  assert_true(not a.active, "the bomb arrow is consumed at the strike")
  -- the bomb's blast flash AND the device's flash: two booms spawned
  local booms = #ctx.ents.booms
  assert_true(booms >= 2,
    "the bomb blast and the device's push both fire (booms "
    .. booms .. " live)")
  assert_true(p.vy < -config.pusher.push,
    "the two shoves stack for a bigger launch (vy " .. p.vy .. ")")
end

-- ==== 9. the strike fires the device without shaking the camera ====
-- The flash ring is the device's own light, not a blast: it flags
-- no_shake, so an arrow striking the device leaves the frame steady.
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ctx = g.ctx
  local pu = test_device(g)
  ctx.player.x, ctx.player.y = pu.x + 4, pu.y - 13
  run_steps(env, 2)
  ctx.ents.booms = {}
  g.cam.shake_t = nil
  local a = rig_arrow(g, "normal", 0, 6)
  run_until_consumed(env, a, 5)
  local b = ctx.ents.booms[1]
  assert_true(b ~= nil, "the strike still spawns the device's flash ring")
  assert_true(b.no_shake == true, "the strike boom opts out of the shake")
  assert_true(g.cam.shake_t == nil,
    "striking the device left the camera steady (shake_t "
      .. tostring(g.cam.shake_t) .. ")")
end

print("pusher tests: " .. PASS .. " passed, " .. FAIL .. " failed")
if FAIL > 0 then os.exit(1) end
