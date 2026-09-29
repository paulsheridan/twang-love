-- Stuck-arrow tests (deterministic, headless; requires LuaJIT).
--
-- Covers how an arrow reads once it has struck terrain:
--   1. a wall hit buries the tip IN the wall (arrows.embed_px past the
--      face, inside the tile) -- it no longer rests a few px clear
--   2. a floor hit buries it just under the surface the same way
--   3. the face itself is unchanged, so the perch still works: an
--      embedded wall arrow catches a fall and hugs the wall
--   4. the shaft draws BUCKLED: two segments meeting at a kink, scaled
--      by the impact speed and capped, and dead straight on a soft tap
--   5. a struck enemy bleeds out BOTH sides: the existing entry spray
--      comes back against the shot, a matching exit spray leaves along
--      it, and the exit point is the far face of the body
--
-- Usage (from the project root): luajit tests/arrows_test.lua

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

local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

local function run_draw(env)
  env.love.draw()
end

-- A hand-made arrow already in flight, `n` px short of the target it is
-- about to hit (arrows that were fired by the bow would arc off this
-- line; these fly straight at it).
local function flying_arrow(g, x, y, vx, vy, kind)
  local a = {
    x = x, y = y, vx = vx, vy = vy, active = true, stuck = false,
    bounced = 0, sdx = vx ~= 0 and 1 or 0, sdy = 0, spin = 0,
    lt = 300, kind = kind or "normal", traveled = 0,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

-- Steps until the arrow sticks (or gives up), so a test can inspect
-- where the impact left it.
local function step_until_stuck(env, g, a, limit)
  for _ = 1, (limit or 30) do
    run_steps(env, 1)
    if a.stuck or not a.active then return end
  end
end

-- A solid wall column in the open area right of the spawn wall: its 8px
-- sub-cells at column 11 (x=88..96), rows 22..27 (y=176..223).
local function rig_wall(g)
  local w = g.ctx.world
  local solid_id = w:tile(0, 28)  -- the spawn-area wall/floor sub-tile id
  for dr = 22, 27 do
    w:set_tile(11, dr, solid_id)
  end
  return w
end

-- ==== 1. a wall hit buries the tip in the wall ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false  -- no laser beams in the way
  local w = rig_wall(g)
  local a = flying_arrow(g, 60, 200, 8, 0)
  step_until_stuck(env, g, a)
  assert_true(a.stuck, "the arrow embedded in the rigged wall")
  assert_true(a.face == 88,
    "the wall face is still recorded at the tile edge (face "
      .. tostring(a.face) .. ")")
  assert_true(a.x == a.face + config.arrows.embed_px,
    "the tip sits embed_px INSIDE the wall (x " .. a.x .. ", face "
      .. tostring(a.face) .. ")")
  assert_true(w:solid_for_arrow(a.x, a.y),
    "the buried tip is really within the wall tile")
  -- the shaft still has to be visible: the arrow reaches out from the
  -- face by more than its own length
  assert_true(a.face - a.x < 12,
    "the shaft still reaches out of the wall")
end

-- ==== 2. a floor hit buries the tip under the surface ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local w = g.ctx.world
  -- the spawn-area floor: the arrow drops into it and stops
  local a = flying_arrow(g, 140, 190, 0, 4)
  step_until_stuck(env, g, a)
  assert_true(a.stuck, "the arrow embedded in the floor")
  -- the tile it stopped in, read back from where the tip came to rest
  local face = math.floor((a.y - config.arrows.embed_px) / 8) * 8
  assert_true(math.abs(a.y - (face + config.arrows.embed_px)) < 1e-9,
    "the tip rests embed_px below the floor's top edge (y " .. a.y .. ")")
  assert_true(w:solid_for_arrow(a.x, a.y),
    "the buried tip is really within the floor tile")
  assert_true(a.face == nil,
    "a floor hit still records no wall face (so it is never a perch)")
end

-- ==== 3. the perch survives the embed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  rig_wall(g)
  local a = flying_arrow(g, 60, 200, 8, 0)
  step_until_stuck(env, g, a)
  local p = g.ctx.player
  -- drop the body onto the embedded arrow, hugging the wall it is in
  p.x, p.y, p.vx, p.vy, p.gr = a.face - p.w, a.y - p.h - 4, 0, 6, false
  run_steps(env, 6)
  assert_true(p.arrow_stand ~= nil and p.arrow_stand.arrow == a,
    "an embedded wall arrow still catches the fall as a perch")
  assert_true(p.y == a.y - p.h and not p.gr and p.vy == 0,
    "the perch pins the feet to the arrow and is still not ground")
  assert_true(p.x == a.face - p.w,
    "the hug still pulls the body flush to the recorded face (x "
      .. p.x .. ")")
end

-- ==== 4. the shaft draws buckled, harder the faster the hit ====
-- The world pass draws the embedded arrow's shaft as two segments
-- meeting at a kink; with the enemies off and nothing else alive those
-- two lines are the only ones the frame draws.
do
  local function shaft(env, g, vx)
    rig_wall(g)
    local a = flying_arrow(g, 60, 200, vx, 0)
    step_until_stuck(env, g, a)
    local sink = {}
    env.TWANG_TEST.record_lines(sink)
    run_draw(env)
    env.TWANG_TEST.record_lines(nil)
    return a, sink
  end

  -- The drawn kink, and how far it sits off the straight tail-tip line.
  -- Every point is floored to whole pixels, so a shaft that is straight
  -- in float still reads a fraction of a pixel off after rounding: the
  -- test bands the two cases apart rather than expecting an exact zero.
  local function bend_px(lines)
    if #lines ~= 2 then return nil end
    local function ends(l) return {l[1], l[2]}, {l[3], l[4]} end
    local p1a, p1b = ends(lines[1])
    local p2a, p2b = ends(lines[2])
    local same = function(p, q) return p[1] == q[1] and p[2] == q[2] end
    local kink, tail, tip
    if same(p1a, p2a) then kink, tail, tip = p1a, p1b, p2b
    elseif same(p1a, p2b) then kink, tail, tip = p1a, p1b, p2a
    elseif same(p1b, p2a) then kink, tail, tip = p1b, p1a, p2b
    elseif same(p1b, p2b) then kink, tail, tip = p1b, p1a, p2a
    end
    if not kink then return nil end
    local span = math.sqrt((tip[1]-tail[1])^2 + (tip[2]-tail[2])^2)
    return math.abs((kink[1]-tail[1])*(tip[2]-tail[2])
      - (kink[2]-tail[2])*(tip[1]-tail[1])) / span
  end

  -- a hard hit: the shaft is visibly kinked, within the configured cap
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  g.ctx.config.enemies.enabled = false
  local fast, lines = shaft(env, g, 18)
  assert_true(fast.stuck, "the fast arrow embedded")
  assert_true(#lines == 2,
    "the embedded shaft draws as two segments (" .. #lines .. " lines)")
  local fast_bend = bend_px(lines)
  assert_true(fast_bend ~= nil and fast_bend > 1,
    "a full-power hit leaves the shaft bent off its flight line ("
      .. ("%.2f"):format(fast_bend or -1) .. "px)")
  assert_true(fast_bend ~= nil and fast_bend <= config.arrows.bend_max_px,
    "the kink stays within arrows.bend_max_px ("
      .. ("%.2f"):format(fast_bend or -1) .. "px)")

  -- a soft tap (under arrows.bend_speed): no kick at all, the shaft
  -- reads straight to within a pixel of rounding
  local env2 = Harness.boot()
  local g2 = env2.TWANG_TEST.game
  g2.ctx.config.enemies.enabled = false
  local soft, lines2 = shaft(env2, g2, 4)
  assert_true(soft.stuck, "the soft arrow embedded")
  assert_true(#lines2 == 2, "the soft shaft still draws as two segments")
  local soft_bend = bend_px(lines2)
  assert_true(soft_bend ~= nil and soft_bend < 1,
    "a soft tap leaves the shaft dead straight ("
      .. ("%.2f"):format(soft_bend or -1) .. "px)")
end

-- ==== 5. a struck enemy bleeds out both sides ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local w, ents, p = g.ctx.world, g.ctx.ents, g.ctx.player
  g.ctx.config.enemies.enabled = false
  -- a clear lane of open sky to shoot down, well clear of the player
  for c = 14, 46 do
    w:set_tile(c, 20, 0)
    w:set_tile(c, 21, 0)
  end
  ents.pushers, ents.movers, ents.winches = {}, {}, {}
  -- one body standing in it
  ents.enemies = {}
  local e = { type = "melee", x = 200, y = 160, w = 12, h = 16,
    vx = 0, vy = 0, gr = true, facing = 1, state = "patrol",
    shoot_cd = 0, last_known = nil }
  table.insert(ents.enemies, e)
  -- and a full-power shot straight through the middle of it
  p.x, p.y, p.vx, p.vy = 100, 212, 0, 0
  local a = flying_arrow(g, 150, 168, 18, 0)
  step_until_stuck(env, g, a, 12)
  assert_true(#ents.enemies == 0 and not a.active, "the shot killed the body")

  local cfg = config.particles
  local back, through, far = 0, 0, 0
  for _, pt in ipairs(ents.particles) do
    if pt.col == cfg.blood_colour then
      -- a +x shot: the entry spray comes back to the left, the exit
      -- spray is thrown on to the right
      if pt.vx < 0 then back = back + 1
      elseif pt.vx > 0 then through = through + 1 end
      -- the exit spray leaves at the far face of the body (x=212)
      if pt.x > e.x + e.w - 1 then far = far + 1 end
    end
  end
  assert_true(back == cfg.blood_count,
    "the entry spray still throws blood against the shot ("
      .. back .. " of " .. cfg.blood_count .. ")")
  assert_true(through == cfg.blood_count,
    "a matching spray leaves the far side along the shot ("
      .. through .. " of " .. cfg.blood_count .. ")")
  assert_true(far == cfg.blood_count,
    "the exit spray spawns at the far face of the body, not the entry "
      .. "(" .. far .. " of " .. cfg.blood_count .. " past it)")
end

print(("arrows tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
