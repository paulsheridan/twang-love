-- Impact aftermath tests (deterministic, headless; requires LuaJIT).
--
-- Covers the burning spots a hit on level geometry leaves behind (see
-- Particles.aftermath / Particles.update_burns, hooked from the laser's
-- wall end, Rockets.blast and the bomb arrow's detonate_bomb):
--   1. a spot anchors at the nearest burnt face, aimed off it
--   2. its sparks keep flying for a second or so, off the surface
--   3. near-wall blasts smoke: black puffs that rise (near-zero gravity)
--   4. a blast in open air anchors nothing
--   5. the spot ages out: emissions stop, the spot is gone
--   6. integration: a rocket blast near a wall and the bomb arrow's
--      detonation both leave burning spots
--
-- Usage (from the project root): luajit tests/aftermath_test.lua

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
local acfg = config.particles

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

-- ==== 1. a spot anchors at the nearest burnt face ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  -- the spawn-area floor is at y=224: anchor a blast above it
  local ents = g.ctx.ents
  local world = g.ctx.world
  Particles = env.require("src.particles")
  local n0 = #ents.burns
  Particles.aftermath(ents, world, p.x + 20, 208, true)
  assert_true(#ents.burns == n0 + 1, "the blast near a floor anchors a spot")
  local s = ents.burns[#ents.burns]
  assert_true(s.smoke, "a blast's spot smokes")
  -- the spot sits at the floor face it found and aims off it (up)
  assert_true(s.dy < 0, "the sparks aim off the floor (dy " .. s.dy .. ")")
  assert_true(math.abs(s.y - 224) < 8, "the spot pinned to the burnt face (y "
    .. s.y .. ")")
end

-- ==== 2. sparks keep flying for a second or so ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  local ents = g.ctx.ents
  Particles = env.require("src.particles")
  Particles.aftermath(ents, g.ctx.world, p.x + 4, 218, false)
  -- the spot's flecks fly off the surface (up, away from the floor)
  local peaking = 0
  local off_surface = false
  for _ = 1, acfg.aftermath_steps do
    local n0 = #ents.particles
    step(env)
    if #ents.particles > n0 then peaking = peaking + 1 end
    for _, pt in ipairs(ents.particles) do
      if pt.vy < -0.5 then off_surface = true end
    end
  end
  assert_true(peaking >= 6,
    "sparks kept flying long after the impact (" .. peaking .. " emissions)")
  assert_true(off_surface, "the sparks flew off the burnt surface")
  -- the spot is gone at the end of its life
  assert_true(#ents.burns == 0, "the spot aged out within its lifetime")
end

-- ==== 3. near-wall blasts smoke, and the smoke rises ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  local ents = g.ctx.ents
  Particles = env.require("src.particles")
  Particles.aftermath(ents, g.ctx.world, p.x + 4, 220, true)
  -- smoke puffs: black-ish, chunk, rising against near-zero gravity
  for _ = 1, acfg.after_spark_every + acfg.after_smoke_every + 4 do
    step(env)
  end
  local rising = false
  for _, pt in ipairs(ents.particles) do
    if pt.g == acfg.after_smoke_g and pt.vy < 0 then rising = true end
  end
  assert_true(rising, "the smoke from the blast rises")
end

-- ==== 4. a blast in open air leaves no burning remains ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  local ents = g.ctx.ents
  Particles = env.require("src.particles")
  -- open sky, well above the terrain
  Particles.aftermath(ents, g.ctx.world, 140, 80, true)
  assert_true(#ents.burns == 0,
    "a blast with no terrain nearby anchors nothing")
end

-- ==== 5. integration: the blasts anchor spots, open air does not ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  local ents = g.ctx.ents
  -- a rocket blast right above the floor: boom + burning spot + smoke
  local Rockets = env.require("src.rockets")
  local n0 = #ents.burns
  Rockets.blast(g.ctx, p.x + 20, 220, 24, 0)
  assert_true(#ents.burns == n0 + 1,
    "a rocket blast near a wall leaves burning remains")
  assert_true(ents.burns[#ents.burns].smoke, "the blast's burn spot smokes")
  -- a mid-air blast (open sky) anchors nothing
  local n1 = #ents.burns
  Rockets.blast(g.ctx, 140, 80, 24, 0)
  assert_true(#ents.burns == n1, "a mid-air blast leaves no remains")
end
do
  -- the bomb arrow's detonation at a surface leaves one too
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = 100, 200, 0, 0
  for _ = 1, 30 do
    step(env)
    if p.gr then break end
  end
  local ents = g.ctx.ents
  local Arrows = env.require("src.arrows")
  local n0 = #ents.burns
  Arrows.detonate_bomb(g.ctx, p.x + 20, 220)
  assert_true(#ents.burns == n0 + 1,
    "a bomb arrow's detonation leaves burning remains")
  assert_true(ents.burns[#ents.burns].smoke, "the bomb arrow's spot smokes")
end

print(("aftermath tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
