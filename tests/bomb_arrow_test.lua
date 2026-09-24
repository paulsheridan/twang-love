-- Bomb arrow tests (deterministic, headless; requires LuaJIT).
--
-- Covers the swap cycle's fourth arrow kind (see Arrows.detonate_bomb /
-- Arrows.step_one / Player.arrow_step):
--   1. the cycle: normal -> rope -> shockwave -> bomb -> normal
--   2. firing the bomb produces a bomb arrow that flies
--   3. terrain detonation: any solid contact detonates (no stick, no
--      bounce), leaving a boom flash at the contact point
--   4. sticky surfaces detonate too (no bounce, no spin-out)
--   5. the blast shoves enemies inside the radius and spares those out;
--      nobody dies to the blast itself
--   6. a direct enemy hit kills the touched enemy (blood) and the blast
--      shoves the rest
--   7. the shock wave shoves the player radially away from the blast
--      centre, additive with linear proximity falloff to the rim;
--      dead-centre pushes up
--   8. the player is never damaged by their own bomb
--   9. the knock rides the winch-throw grace window (the walk cap
--      cannot clamp it) and cuts an attached rope, at blast and at fire
--  10. the blast knocks rockets, bombs and darts off course
--  11. bomb arrows never carry or pick up keys
--
-- Usage (from the project root): luajit tests/bomb_arrow_test.lua

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

local config = dofile("src/config.lua")
local tw = config.tile_size
local blast = config.bomb_arrow

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

-- Places the player on open ground at (x, y) and lets them settle.
local function settle(env, x, y)
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  return p
end

-- ==== 1. the swap cycle includes the bomb ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  assert_true(p.arrow_kind == "normal", "the bow starts on normal arrows")
  local expect = { "rope", "shockwave", "bomb", "normal" }
  for i, kind in ipairs(expect) do
    env.love.keypressed("c")
    step(env)
    assert_true(p.arrow_kind == kind,
      ("swap %d lands on %s (got %s)"):format(i, kind, p.arrow_kind))
  end
end

-- ==== 2. firing the bomb ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.arrow_kind = "bomb"
  local Arrows = env.require("src.arrows")
  Arrows.fire(g.ctx, 0.0, "bomb", 1.0)  -- flat right
  local a = g.ctx.ents.arrows[1]
  assert_true(a ~= nil and a.kind == "bomb" and a.active,
    "firing the bomb spawns a bomb arrow")
  for _ = 1, 10 do
    step(env)
    if not a.active then break end
  end
  assert_true(#g.ctx.ents.booms >= 1,
    "the bomb arrow detonates against the level's terrain")
end

-- ==== 3. terrain detonation: no stick, a boom at the contact ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  -- rig a bomb arrow flying right into the solid wall right of the spawn
  local world = g.ctx.world
  local wall_x
  for x = p.x + 8, p.x + 200, 8 do
    if world:solid_for_arrow(x, p.y + p.h/2) then wall_x = x break end
  end
  assert_true(wall_x ~= nil, "there is a wall ahead to hit")
  local a = {
    x = wall_x - 10, y = p.y + p.h/2, vx = 8, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "bomb", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  local booms = #g.ctx.ents.booms
  local detonated = false
  for _ = 1, 10 do
    step(env)
    if not a.active then detonated = true break end
  end
  assert_true(detonated, "the bomb arrow detonates on the wall")
  assert_true(not a.stuck, "the bomb arrow never embeds")
  assert_true(#g.ctx.ents.booms > booms,
    "the detonation leaves a boom flash")
  local boom = g.ctx.ents.booms[#g.ctx.ents.booms]
  assert_true(boom.r == blast.blast_radius,
    "the flash ring carries the bomb blast radius")
end

-- ==== 4. sticky surfaces detonate (no bounce) ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local world = g.ctx.world
  -- rig a sticky wall ahead of the arrow's path
  local sticky_id
  for t = 1, 255 do
    if world:solid(t) and world:sticky(t) then sticky_id = t break end
  end
  assert_true(sticky_id ~= nil, "the sheet has a sticky tile")
  world:set_tile(math.floor((p.x + 60) / tw), math.floor((p.y + 6) / tw), sticky_id)
  local a = {
    x = p.x + 20, y = p.y + 6, vx = 6, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "bomb", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  local detonated = false
  for _ = 1, 12 do
    step(env)
    if not a.active then detonated = true break end
  end
  assert_true(detonated, "the bomb arrow detonates on a sticky surface")
  assert_true(not a.dying and a.bounced == 0,
    "sticky contact detonates instead of bouncing")
end

-- ==== 5. the blast shoves enemies in radius, spares those outside ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local ents = g.ctx.ents
  local function mk_enemy(x, y)
    return { x = x, y = y, vx = 0, vy = 0, w = config.enemies.width,
      h = config.enemies.height, gr = false, facing = 1, type = "melee",
      shoot_cd = config.enemies.shoot_cooldown, state = "patrol",
      last_known = nil }
  end
  local near = mk_enemy(p.x + 10, p.y)
  local far = mk_enemy(p.x + blast.blast_radius * 2, p.y)
  table.insert(ents.enemies, near)
  table.insert(ents.enemies, far)
  local Arrows = env.require("src.arrows")
  Arrows.detonate_bomb(g.ctx, p.x + 4, p.y + 6)
  local near_alive, far_alive = false, false
  for _, e in ipairs(ents.enemies) do
    if e == near then near_alive = true end
    if e == far then far_alive = true end
  end
  assert_true(near_alive, "the blast never kills on its own")
  assert_true(far_alive, "the enemy outside the blast survives")
  assert_true(near.vx > 0, "the enemy inside the blast was shoved (vx "
    .. near.vx .. ")")
  assert_true(far.vx == 0 and far.vy == 0,
    "the enemy outside the blast was untouched")
end

-- ==== 6. a direct enemy hit kills, then the blast shoves the rest ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local ents = g.ctx.ents
  -- a clean range: the level's own enemies, doors, springs, switches
  -- and terrain out of the lane (the world keeps its own references to
  -- the interactable lists, so clear those directly)
  ents.enemies = {}
  local world = g.ctx.world
  world.doors = {}
  world.springs = {}
  world.switches = {}
  local row = math.floor((p.y + 8) / config.tile_size)
  for c = math.floor((p.x + 40) / config.tile_size),
         math.floor((p.x + 100) / config.tile_size) do
    world:set_tile(c, row, 0)
    world:set_tile(c, row + 1, 0)
  end
  local function mk_enemy(x, y)
    return { x = x, y = y, vx = 0, vy = 0, w = config.enemies.width,
      h = config.enemies.height, gr = false, facing = 1, type = "melee",
      shoot_cd = config.enemies.shoot_cooldown, state = "patrol",
      last_known = nil }
  end
  local target = mk_enemy(p.x + 60, p.y)      -- in the arrow's path
  local bystanding = mk_enemy(p.x + 72, p.y)  -- caught by the blast (the
                                              -- blast at the contact shoves
                                              -- it further along)
  table.insert(ents.enemies, target)
  table.insert(ents.enemies, bystanding)
  local a = {
    x = target.x - 12, y = target.y + 8, vx = 6, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "bomb", traveled = 10,
  }
  table.insert(ents.arrows, a)
  local booms = #ents.booms
  local n0 = #ents.enemies
  for _ = 1, 10 do
    step(env)
    if not a.active then break end
  end
  local target_alive = false
  for _, e in ipairs(ents.enemies) do
    if e == target then target_alive = true end
  end
  assert_true(not target_alive, "the touched enemy dies to the direct hit")
  assert_true(#ents.enemies == 1, "the bystander survives the blast alone")
  assert_true(bystanding.vx > 0, "the bystander was shoved by the blast (vx "
    .. bystanding.vx .. ")")
  assert_true(#ents.booms > booms, "the direct hit detonates the blast")
end

-- ==== 7. the shock wave shoves the player radially away ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local Arrows = env.require("src.arrows")
  -- a blast 20px to the left shoves right, at the falloff's midpoint
  local vx0, vy0 = p.vx, p.vy
  Arrows.detonate_bomb(g.ctx, p.x + p.w/2 - 20, p.y + p.h/2)
  local dx, dy = p.vx - vx0, p.vy - vy0
  assert_true(vx0 == 0 and dy == 0 and dx > 0,
    "a blast to the left shoves the player to the right")
  local expected = blast.push
    * math.max(blast.min_push_scale, 1 - 20 / blast.blast_radius)
  assert_true(dx >= expected - 0.01 and dx <= expected + 0.01,
    "the shove follows the proximity falloff (full at centre)")
  -- a blast at the radius's rim pushes at the floor share
  p.vx, p.vy, p.winch_grace = 0, 0, nil
  local edge = blast.blast_radius - 4
  Arrows.detonate_bomb(g.ctx, p.x + p.w/2 - edge, p.y + p.h/2)
  local edge_push = p.vx
  assert_true(edge_push >= blast.push * blast.min_push_scale - 0.01
    and edge_push <= blast.push * blast.min_push_scale + 0.01,
    "an edge blast pushes at the floor share")
  -- dead centre: straight up
  p.vx, p.vy, p.winch_grace = 0, 0, nil
  Arrows.detonate_bomb(g.ctx, p.x + p.w/2, p.y + p.h/2)
  assert_true(p.vx == 0 and p.vy < 0,
    "a dead-centre blast shoves straight up")
  -- the shove is additive: a fall carries through the launch
  p.vx, p.vy, p.winch_grace = 0, 2, nil
  Arrows.detonate_bomb(g.ctx, p.x + p.w/2, p.y + p.h/2 + 20)
  assert_true(p.vy < -4 and p.vy > -(blast.push + 2),
    "the knock adds to the body's motion (vy " .. p.vy .. ")")
end

-- ==== 8. the player is never damaged by their own bomb ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local hp = p.hp
  local Arrows = env.require("src.arrows")
  Arrows.detonate_bomb(g.ctx, p.x + 2, p.y + 2)
  assert_true(p.hp == hp, "the blast does not hurt the player")
  assert_true(p.invuln == 0, "no i-frames were spent")
end

-- ==== 9. the knock rides the grace window and cuts the rope ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local Arrows = env.require("src.arrows")
  -- an airborne player (as after a vault): the grace holds in the air
  p.gr = false
  Arrows.detonate_bomb(g.ctx, p.x - 30, p.y + p.h/2)
  assert_true(p.winch_grace == blast.shove_grace,
    "the knock starts the grace window")
  local vx0 = p.vx
  step(env)
  assert_true(math.abs(p.vx - vx0) < 0.01,
    "the walk cap cannot clamp the knock during the grace")
  -- the grace lapses after shove_grace (airborne: no landing to cut it)
  for _ = 1, blast.shove_grace + 2 do step(env) end
  assert_true(p.winch_grace == nil,
    "the grace lapses after its window")
  -- an attached rope is cut by the blast (the rig anchors into the real
  -- floor beside the player, stick pointing down into it)
  local world = g.ctx.world
  local anchor_x = p.x + 40
  local floor_y
  for y = math.floor(p.y / tw), g.ctx.world.h do
    if world:solid_at(anchor_x + 4, y * tw + 8) then
      floor_y = y * tw
      break
    end
  end
  assert_true(floor_y ~= nil, "there is floor under the rope anchor")
  local a = {
    x = anchor_x + 4, y = floor_y - 1, vx = 0, vy = -2,
    active = true, stuck = true, bounced = 0,
    sdx = 0, sdy = 1, spin = 0, lt = 30000,
    kind = "rope", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  step(env)
  assert_true(p.rope ~= nil, "the rope attaches for the cut test")
  Arrows.detonate_bomb(g.ctx, p.x + 10, p.y)
  assert_true(p.rope == nil, "the blast cuts an attached rope")
  assert_true(p.rope_cd and p.rope_cd > 0,
    "the rope cooldown blocks an instant re-grab")
  -- firing a bomb arrow cuts an attached rope too (mobility tool)
  local a2 = {
    x = anchor_x + 4, y = floor_y - 1, vx = 0, vy = -2,
    active = true, stuck = true, bounced = 0,
    sdx = 0, sdy = 1, spin = 0, lt = 30000,
    kind = "rope", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a2)
  p.rope_cd = 0
  step(env)
  assert_true(p.rope ~= nil, "the rope re-attaches for the fire test")
  Arrows.fire(g.ctx, 0.0, "bomb", 1.0)
  assert_true(p.rope == nil, "firing a bomb arrow cuts the rope")
end

-- ==== 10. the blast knocks rockets, bombs and darts off course ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local ents = g.ctx.ents
  local rocket = {
    x = p.x + 20, y = p.y, hx = 0, hy = -1, state = "hover",
    climbed = 24, hover_t = 12, active = true, lt = 150, trail_t = 2,
    kx = 0, ky = 0,
  }
  local bomb = { x = p.x + 20, y = p.y + 30, vx = 0, vy = 0, fuse = 90,
    active = true }
  local dart = { x = p.x + 20, y = p.y - 30, vx = 0, vy = 4, active = true }
  table.insert(ents.rockets, rocket)
  table.insert(ents.bombs, bomb)
  table.insert(ents.e_arrows, dart)
  local Arrows = env.require("src.arrows")
  Arrows.detonate_bomb(g.ctx, p.x + 4, p.y)
  assert_true(rocket.kx > 0, "the blast knocked the rocket (kx "
    .. rocket.kx .. ")")
  assert_true(bomb.vx > 0, "the blast knocked the bomb (vx "
    .. bomb.vx .. ")")
  assert_true(dart.vx > 0, "the blast scattered the dart (vx "
    .. dart.vx .. ")")
end

-- ==== 11. bomb arrows never carry or pick up keys ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  local ents = g.ctx.ents
  -- a carried key stays with the player when a bomb is fired
  local carried = { x = 0, y = 0, taken = true, g = 1 }
  p.key = carried
  local Arrows = env.require("src.arrows")
  Arrows.fire(g.ctx, 0.75, "bomb", 1.0)  -- straight up (open sky)
  local a = ents.arrows[#ents.arrows]
  assert_true(a ~= nil and a.kind == "bomb", "the bomb arrow fired")
  assert_true(p.key == carried, "the carried key stayed with the player")
  assert_true(a.key == nil, "the bomb arrow took no key")
  -- a bomb arrow flying past a world key does not snatch it
  local world_key = { x = p.x + 20, y = p.y + 6, taken = false, g = 2 }
  table.insert(ents.keys, world_key)
  local a2 = {
    x = p.x, y = world_key.y, vx = 6, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "bomb", traveled = 0,
  }
  table.insert(ents.arrows, a2)
  step(env)
  assert_true(not world_key.taken,
    "the bomb arrow's tip never picked up the key")
  assert_true(a2.key == nil, "the bomb arrow carries nothing")
end

-- ==== 12. rendering a bomb arrow and its boom is well-formed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = settle(env, 200, 100)
  p.arrow_kind = "bomb"
  local a = {
    x = p.x + 30, y = p.y, vx = 6, vy = -1,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "bomb", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  local Arrows = env.require("src.arrows")
  Arrows.detonate_bomb(g.ctx, p.x + 60, p.y)
  step(env)
  assert_true(true, "the draw path survives a bomb arrow and boom")
end

print(("bomb arrow tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
