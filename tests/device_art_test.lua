-- Device art tests (deterministic, headless).
--
-- Pins the art pipeline behind the stand-in sprites:
--
--   * an art tileset draws at the cell size IT declares, so a device can
--     be painted bigger than the 16px block it belongs to (the 32x32
--     updraft/outdraft) without a special case in the loader;
--   * config.art_files is a list, so the 16x16 sheet and the 32x32 one
--     can sit side by side and still resolve every role by name;
--   * a pusher takes its art from its VARIANT, so updraft and outdraft
--     are drawn differently, with the legacy shared "pusher" role as a
--     fallback for a sheet that only declares that one;
--   * a cell larger than the block is drawn STANDING ON the block (its
--     bottom edge on the block's bottom edge), not centred on it, or a
--     32x32 device would float half a block above the tile it pushes from;
--   * a tile the author placed still beats the role's art, so a level
--     that paints its own device keeps its own picture.
--
-- Usage (from the project root): luajit tests/device_art_test.lua

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

local env = Harness.boot("tests/object_kinds_fixture.json")
local g = env.TWANG_TEST.game
local config = env.require("src.config")
local tiled = env.require("src.tiled")

-- ==== 1. every art file loads, and each role draws at its own size ====
do
  assert_true(#config.art_files >= 2,
    "the global art is a list, so sheets of different cell sizes can sit "
      .. "side by side (got " .. #config.art_files .. " entries)")

  local SMALL = {"switch", "switch_on", "key", "lock", "door", "spring",
                 "spring_ext", "winch", "gun"}
  for _, kind in ipairs(SMALL) do
    local rec = g.art[kind]
    assert_true(rec ~= nil and rec.w == 16 and rec.h == 16,
      "the " .. kind .. " is a 16x16 cell (got "
        .. (rec and (rec.w .. "x" .. rec.h) or "no art") .. ")")
    assert_true(rec ~= nil and rec.image == "maps/chars.png",
      "the " .. kind .. " came from the 16x16 sheet (got "
        .. tostring(rec and rec.image) .. ")")
  end

  for _, kind in ipairs({"updraft", "outdraft"}) do
    local rec = g.art[kind]
    assert_true(rec ~= nil and rec.w == 32 and rec.h == 32,
      "the " .. kind .. " is a 32x32 cell (got "
        .. (rec and (rec.w .. "x" .. rec.h) or "no art") .. ")")
    assert_true(rec ~= nil and rec.image == "maps/drafts32.png",
      "the " .. kind .. " came from the 32x32 sheet (got "
        .. tostring(rec and rec.image) .. ")")
  end
end

-- ==== 2. the big cells survive the loader on their own ====
-- The role table is built by src/tiled.lua, not by the game, so a 32x32
-- sheet has to load through the same path a 16x16 one does.
do
  local art = tiled.load_artset("maps/drafts32.tsx")
  assert_true(art.updraft ~= nil and art.updraft.w == 32
    and art.updraft.h == 32,
    "a 32x32 art tileset loads (updraft is "
      .. (art.updraft and (art.updraft.w .. "x" .. art.updraft.h)
        or "missing") .. ")")
  assert_true(art.outdraft ~= nil and art.outdraft.w == 32,
    "both big devices are declared in the 32x32 sheet")

  -- the 16x16 sheet on its own has no variant roles, which is exactly
  -- why level.lua keeps a fallback to the shared "pusher" role
  local small = tiled.load_artset("maps/chars.tsx")
  assert_true(small.pusher ~= nil and small.updraft == nil,
    "the 16x16 sheet carries the legacy pusher role and no variants "
      .. "(so the fallback has something to fall back to)")
end

-- ==== 3. a pusher takes its art from its variant ====
do
  local by_variant = {}
  for _, pu in ipairs(g.ents.pushers) do
    by_variant[pu.variant] = by_variant[pu.variant] or {}
    table.insert(by_variant[pu.variant], pu)
  end
  for _, variant in ipairs({"updraft", "outdraft"}) do
    local list = by_variant[variant] or {}
    assert_true(#list > 0,
      "the fixture's " .. variant .. " points loaded (got " .. #list .. ")")
    for i, pu in ipairs(list) do
      assert_true(pu.art ~= nil and pu.art.kind == variant,
        variant .. " #" .. i .. " draws the " .. variant .. " art (got "
          .. tostring(pu.art and pu.art.kind) .. ")")
    end
  end
  -- the block a pusher owns is 16px whatever its art measures: the
  -- physics and the launch column are sized in art cells, not by the
  -- sprite. It is snapped to the terrain grid, as every placed object is.
  for _, pu in ipairs(g.ents.pushers) do
    assert_true(pu.x % config.tile_size == 0 and pu.y % config.tile_size == 0,
      "a " .. pu.variant .. " block stays on the " .. config.tile_size
        .. "px grid at " .. pu.x .. "," .. pu.y)
  end
end

-- ==== 4. a big cell is drawn standing on its block ====
-- A 32x32 device is 16px taller than its block, so it is drawn with its
-- bottom edge on the block's bottom edge: the sprite reaches one block
-- further UP (where the launch is) and is centred across the block. A
-- 16x16 device is not moved at all.
do
  local draws = {}
  local gfx = env.love.graphics
  local real_draw = gfx.draw
  gfx.draw = function(image, quad, x, y, ...)
    if type(quad) == "table" and type(x) == "number" then
      draws[#draws + 1] = {x = x, y = y}
    end
    return real_draw(image, quad, x, y, ...)
  end
  local ok, err = pcall(env.love.draw)
  gfx.draw = real_draw
  assert_true(ok, "the world pass draws with a 32x32 device in it ("
    .. tostring(err) .. ")")

  local function drawn_at(x, y)
    for _, d in ipairs(draws) do
      if d.x == x and d.y == y then return true end
    end
    return false
  end

  local big, small = 0, 0
  for _, pu in ipairs(g.ents.pushers) do
    local aw = (pu.art and pu.art.w) or config.art_size
    local ah = (pu.art and pu.art.h) or config.art_size
    -- the rule under test, as src/render/world.lua grounded_art has it:
    -- centred across the block, standing on its bottom edge
    local ax = pu.x - math.max(0, (aw - config.art_size) / 2)
    local ay = pu.y - math.max(0, ah - config.art_size)
    if drawn_at(ax, ay) then
      big = big + 1
    else
      small = small + 1
      print("  (no draw at " .. ax .. "," .. ay .. " for a "
        .. pu.variant .. " block at " .. pu.x .. "," .. pu.y .. ")")
    end
  end
  assert_true(big > 0 and small == 0,
    "every pusher is drawn standing on its block, centred across it ("
      .. big .. " placed, " .. small .. " missed)")
end

-- ==== 5. a tile the author placed still wins over the role art ====
-- The legacy level paints its pushers with 8x8 tiles carrying the kind.
-- The art a map brings for itself is the author's explicit choice, so it
-- outranks the role name -- the 32x32 stand-ins are a default, not an
-- override.
do
  local legacy = Harness.boot()
  local lg = legacy.TWANG_TEST.game
  local painted = 0
  for _, pu in ipairs(lg.ents.pushers) do
    if pu.art ~= nil and pu.art.w == 8 then painted = painted + 1 end
  end
  assert_true(painted > 0,
    "a pusher with a tile placed on it keeps that tile's art (got "
      .. painted .. " of " .. #lg.ents.pushers .. ")")
end

print(("device art tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
