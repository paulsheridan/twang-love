-- Bounce-surface tests (deterministic, headless; requires LuaJIT).
--
-- Covers the `bounce` tile property -- arrows REFLECT off a bounce tile
-- instead of embedding in it -- alongside `solid`, the two flags levels
-- author on a wall:
--   1. the loader reads both property names: "bounce" and the legacy
--      "sticky" spelling both land on the one flag, and "solid" stays
--      independent of it
--   2. a bounce-only tile (no "solid") is still an arrow surface, so an
--      author who marks only "bounce" gets a reflection rather than an
--      arrow sailing quietly through -- but it blocks no bodies
--   3. an arrow striking a bounce wall reflects: velocity flips, the
--      bounce counter advances, and the arrow never embeds
--   4. same for a bounce-only tile, and same for the legacy "sticky"
--      spelling, so the old spritesheet levels keep bouncing
--   5. a reflected arrow is never a perch: it does not stick, so it
--      cannot catch a fall the way an arrow embedded in a wall does
--
-- Usage (from the project root): luajit tests/bounce_test.lua

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

-- Gids in tests/bounce_fixture.json (tests/bounce_tiles.tsx, firstgid 1):
--   1 solid        2 solid+bounce        3 bounce        4 solid+sticky
local PLAIN, BOUNCE, BOUNCE_ONLY, LEGACY = 1, 2, 3, 4

-- The open area right of the spawn wall, where tests/arrows_test rigs its
-- wall: column 11 (x=88..96), rows 22..27 (y=176..223). The cells are
-- cleared first so nothing the level already placed can answer for them.
local function rig_column(w, gid)
  for r = 22, 27 do
    w:set_tile(11, r, 0)
    w:set_tile(11, r, gid)
  end
  return w
end

-- The fixture's tile records, loaded through the real loader, grafted into
-- a booted world's id space so the gameplay cases can place them. The keys
-- are the fixture gids, which no legacy map uses.
local function graft(world)
  local level = dofile("src/tiled.lua").load("tests/bounce_fixture.json")
  for key, rec in pairs(level.tiles_by_key) do
    world.tiles_by_key[key] = rec
  end
  return world
end

-- A hand-made arrow already in flight, `n` px short of the target (an
-- arrow fired by the bow would arc off this line).
local function flying_arrow(g, x, y, vx, vy)
  local a = {
    x = x, y = y, vx = vx, vy = vy, active = true, stuck = false,
    bounced = 0, sdx = vx ~= 0 and 1 or 0, sdy = 0, spin = 0,
    lt = 300, kind = "normal", traveled = 0,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

-- Steps until the arrow has bounced at least once (or gives up), so a test
-- can inspect the reflection. A wall hit in the same frame is the thing
-- under test, so this is short: the arrow flies ~8px a step.
local function step_until_bounce(env, a, limit)
  for _ = 1, (limit or 20) do
    env.love.update(1/30)
    env.love.draw()
    if a.bounced > 0 or not a.active then return end
  end
end

-- ==== 1. the loader reads solid and bounce ====
do
  local level = dofile("src/tiled.lua").load("tests/bounce_fixture.json")
  local rec = level.tiles_by_key

  assert_true(rec[PLAIN] ~= nil and rec[PLAIN].solid == true
    and rec[PLAIN].bounce == nil,
    "a plain solid tile is solid and not a bounce surface")
  assert_true(rec[BOUNCE] ~= nil and rec[BOUNCE].solid == true
    and rec[BOUNCE].bounce == true,
    "solid + bounce reads both flags")
  assert_true(rec[BOUNCE_ONLY] ~= nil and rec[BOUNCE_ONLY].solid == nil
    and rec[BOUNCE_ONLY].bounce == true,
    "bounce alone does not imply solid")
  assert_true(rec[LEGACY] ~= nil and rec[LEGACY].solid == true
    and rec[LEGACY].bounce == true,
    "the legacy 'sticky' spelling still marks a bounce surface")

  -- the grid really carries the fixture: the bounce tile is placed at (1,1)
  local level2 = dofile("src/tiled.lua").load("tests/bounce_fixture.json")
  local row = level2.map[2]
  assert_true(tonumber(row:sub(1*4 + 1, 1*4 + 4), 16) == BOUNCE,
    "the bounce tile landed in the grid where the map put it")
end

-- ==== 2. a bounce tile is an arrow surface, and only that ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local w = graft(g.ctx.world)
  rig_column(w, BOUNCE_ONLY)

  -- the cell's centre: column 11 spans x 88..96, row 22 spans y 176..184
  local cx, cy = 92, 180
  assert_true(w:solid_for_arrow(cx, cy),
    "a bounce-only tile is solid for arrows even without 'solid'")
  assert_true(not w:solid_at(cx, cy),
    "a bounce-only tile blocks no bodies without 'solid'")
  assert_true(w:bounce(w:tile(11, 22)),
    "World:bounce answers for the bounce tile")
  -- the legacy accessor asks the same question, so tooling written
  -- against the old name keeps agreeing with the new one
  assert_true(w:sticky(w:tile(11, 22)) == w:bounce(w:tile(11, 22)),
    "World:sticky and World:bounce agree (legacy spelling kept working)")
  assert_true(w:solid(w:tile(11, 22)) == false,
    "the bounce tile itself is not flagged solid")

  -- solid + bounce blocks bodies as well as arrows
  rig_column(w, BOUNCE)
  assert_true(w:solid_at(cx, cy) and w:solid_for_arrow(cx, cy)
    and w:bounce(w:tile(11, 22)),
    "a solid bounce wall blocks bodies, blocks arrows and reflects them")
end

-- ==== 3. an arrow reflects off a bounce wall instead of embedding ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false  -- no laser beams in the way
  local w = graft(g.ctx.world)
  rig_column(w, BOUNCE)

  local a = flying_arrow(g, 60, 180, 8, 0)
  step_until_bounce(env, a)
  assert_true(a.bounced == 1,
    "the arrow counted exactly one bounce off the wall (bounced "
      .. tostring(a.bounced) .. ")")
  assert_true(a.vx < 0,
    "the arrow's horizontal velocity was reflected (vx " .. a.vx .. ")")
  assert_true(not a.stuck,
    "a bounce surface never lets the arrow embed")
  assert_true(a.face == nil,
    "a reflected arrow records no wall face, so it can never perch")
  assert_true(a.active,
    "the arrow survives its first bounce (max_bounces is "
      .. tostring(config.arrows.max_bounces) .. ")")
end

-- ==== 4. a bounce-only tile reflects too, and so does legacy sticky ====
for _, case in ipairs({
  { gid = BOUNCE_ONLY, label = "a bounce-only tile" },
  { gid = LEGACY,      label = "the legacy 'sticky' tile" },
}) do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local w = graft(g.ctx.world)
  rig_column(w, case.gid)

  local a = flying_arrow(g, 60, 180, 8, 0)
  step_until_bounce(env, a)
  assert_true(a.bounced == 1 and a.vx < 0 and not a.stuck,
    "an arrow reflects off " .. case.label .. " and never embeds (bounced "
      .. tostring(a.bounced) .. ", vx " .. tostring(a.vx) .. ", stuck "
      .. tostring(a.stuck) .. ")")
end

-- ==== 5. a reflected arrow never becomes a perch ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local w = graft(g.ctx.world)
  rig_column(w, BOUNCE)

  -- fly the arrow at the wall, then walk the player into where an
  -- embedded arrow would offer a stand
  local a = flying_arrow(g, 60, 180, 8, 0)
  step_until_bounce(env, a)
  -- it leaves the bounce surface instead of settling in it (an ordinary
  -- wall further along the flight may well take it -- that is the point,
  -- the bounce surface itself never holds it)
  for _ = 1, 4 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(a.x < 88 and not a.stuck,
    "the reflected arrow leaves the bounce column still flying (x "
      .. tostring(a.x) .. ")")
  local p = g.ctx.player
  p.x, p.y = 96, 160
  p.vx, p.vy = 0, 4
  p.gr = false
  for _ = 1, 20 do
    env.love.update(1/30)
    env.love.draw()
  end
  assert_true(not p.arrow_stand,
    "no arrow stand is offered by a surface arrows bounce off")
end

print("bounce tests: " .. PASS .. " passed, " .. FAIL .. " failed")
os.exit(FAIL == 0 and 0 or 1)
