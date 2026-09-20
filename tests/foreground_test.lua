-- Foreground overlay tests (deterministic, headless; requires LuaJIT).
--
-- Covers the visual "Foreground" Tiled layer (docs/tiled-format.md,
-- World:foreground_step / Render.foreground), exercised on the
-- farmhouse map (loaded directly):
--   1. the layer is purely visual: overlay tiles never collide (even
--      when the tileset flags them solid), while terrain still does
--   2. walking behind any overlay tile fades the WHOLE layer out
--      smoothly (config.foreground), so the avatar stays readable
--   3. stepping out eases the layer back to opaque
--
-- Usage (from the project root): luajit tests/foreground_test.lua

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

local env = Harness.boot()
local g = env.TWANG_TEST.game
g:load_level("maps/farmhouse.json")
local w = g.ctx.world
local p = g.ctx.player

-- scan helpers over the map's tile columns/rows
local function find_tile(test)
  for r = 0, w.h - 1 do
    for c = 0, w.w - 1 do
      if test(c, r) then return c, r end
    end
  end
end

local function step_at(x, y, n)
  for _ = 1, (n or 1) do
    p.x, p.y, p.vx, p.vy = x, y, 0, 0  -- pinned: the fade sees a still player
    env.love.update(1/30)
    env.love.draw()
  end
end

-- ==== 1. the overlay never collides, terrain still does ====
local fc, fr = find_tile(function(c, r)
  return w:fg_tile(c, r) ~= 0 and w:tile(c, r) == 0
end)
assert_true(fc ~= nil, "the map has a foreground-only tile")
assert_true(not w:solid_at(fc*16 + 8, fr*16 + 8),
  "an overlay tile blocks nothing, even a solid-flagged tile id")
local tc, tr = find_tile(function(c, r)
  return w:solid(w:tile(c, r))
end)
assert_true(tc ~= nil, "the map has solid terrain")
assert_true(w:solid_at(tc*16 + 8, tr*16 + 8),
  "terrain solidity is untouched by the overlay")

-- ==== 2. behind any overlay tile, the whole layer fades out ====
step_at(fc*16, fr*16, 12)  -- 12 steps: past the ~8-step full fade
assert_true(w.fg_alpha == 0, "the layer fades fully out while behind it")

-- the fade eases rather than snapping
g:load_level("maps/farmhouse.json")
w = g.ctx.world
p = g.ctx.player
step_at(fc*16, fr*16, 2)
local a1, a2 = w.fg_alpha, nil
step_at(fc*16, fr*16, 1)
a2 = w.fg_alpha
assert_true(a1 < 1 and a2 < a1, "the fade eases step by step")

-- ==== 3. stepping out fades the layer back in ====
step_at(16, 16, 12)  -- far from any overlay tile
assert_true(w.fg_alpha == 1, "the layer fades back in once the player steps out")

print(("foreground tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
