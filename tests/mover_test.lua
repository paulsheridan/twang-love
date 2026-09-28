-- Mover tests (deterministic, headless; requires LuaJIT).
--
-- Covers the moving blocks (src/movers.lua; level1's demo pair: the
-- auto cycler `mover_auto` resting at tile (4, 42) running 12 tiles
-- right, and the trigger lift `mover_lift` resting at tile (14, 44),
-- 1x2 tiles, running 6 tiles down):
--
--   1. the scan: both demo movers come in with the right shape
--   2. solidity: the block's current box is solid ground; a trigger
--      mover parked at rest is recessed to arrows
--   3. the auto mover cycles: out to the far end, an exact pause, back,
--      an exact pause, out again
--   4. the rider: a player standing on a moving block is carried (x
--      rides a horizontal mover, y rides a vertical one), and jumping
--      off severs the ride
--   5. the trigger: a landing (grounded rising edge) fires it; a rider
--      who never got off keeps it parked at home; leaving and landing
--      again re-arms it
--   6. the arrow strike: a player arrow tip entering the block is
--      consumed and fires a parked trigger mover; a moving block just
--      eats arrows without re-triggering
--   7. stalls: a body in the block's path (an enemy; the player under a
--      lowering lift) stops the block for the step instead of being
--      crushed; the block resumes when the way clears
--   8. off-room movers freeze (the rooms gate, like the springs)
--
-- Usage (from the project root): luajit tests/mover_test.lua

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

-- level1's demo pair: the auto cycler and the trigger lift.
local function movers(g)
  return g.ctx.ents.movers[1], g.ctx.ents.movers[2]
end

-- Resets a mover to a known state (whole tests run from here).
local function reset(m, px, state, dirn)
  m.px = px or 0
  m.state = state or "rest"
  m.dirn = dirn or 1
  m.t, m.f = 0, 0
  m.bx = m.ox + m.dx * m.px
  m.by = m.oy + m.dy * m.px
end

-- ==== 1. the scan ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local auto, lift = movers(g)
  assert_true(auto ~= nil and lift ~= nil, "level1 scans both demo movers")
  assert_true(#g.ctx.ents.movers == 2,
    "exactly two mover objects are placed (got "
    .. tostring(#g.ctx.ents.movers) .. ")")
  assert_true(auto.mode == "auto", "the Mover class resolves the auto mode")
  assert_true(lift.mode == "trigger",
    "the MoverTrigger class resolves the trigger mode")
  assert_true(auto.ox == 64 and auto.oy == 672,
    "the auto mover rests at tile (4, 42) (got "
    .. tostring(auto.ox) .. ", " .. tostring(auto.oy) .. ")")
  assert_true(auto.dx == 1 and auto.dy == 0,
    "the auto mover's line runs right (wider than tall)")
  assert_true(auto.len == 12 * 16,
    "the auto mover's line is 12 tiles long (got " .. tostring(auto.len) .. ")")
  assert_true(auto.wt == 2 and auto.ht == 1,
    "the auto mover is a 2x1 block (its tiles_w property sizes it)")
  assert_true(lift.ox == 80 and lift.oy == 704,
    "the lift rests at tile (5, 44)")
  assert_true(lift.dx == 0 and lift.dy == 1,
    "the lift's line runs down (its dir property)")
  assert_true(lift.len == 6 * 16, "the lift's line is 6 tiles long")
  assert_true(lift.wt >= 1 and lift.wt <= 3 and lift.ht >= 1
    and lift.ht <= 3,
    "the lift's footprint respects its tiles properties (got "
    .. tostring(lift.wt) .. "x" .. tostring(lift.ht) .. ")")
  assert_true(lift.state == "rest", "the lift starts parked")
  local w = g.ctx.world
  assert_true(w:solid_at(auto.bx + 8, auto.by + 8),
    "the block's current box is solid ground to bodies")
  assert_true(not w:solid_at(auto.bx + 40, auto.by + 8),
    "the open line ahead of the block is not solid")
  assert_true(not w:solid_for_arrow(lift.bx + 8, lift.by + 8),
    "a parked trigger mover is recessed to arrows (tips fly in and strike)")
end

-- ==== 1b. the footprint: properties win, the object's size falls back ====
do
  local Level = require("src.level")
  -- a minimal fake level table (what src/tiled.lua hands Level.build);
  -- objects carry ow/oh like the loader does (the object's placed size)
  local fake = {
    MAP_W = 8, MAP_H = 2,
    map = { string.rep("00", 8), string.rep("00", 8) },
    special = {},
    objects = {
      -- explicit tiles_w/tiles_h properties win over the placed size
      -- (and direction is explicit only: a WIDE block can run DOWN)
      { kind = "mover", x = 16, y = 16, name = "t1",
        distance = 4, tiles_w = 3, tiles_h = 2, dir = "down",
        ow = 16, oh = 16 },
      -- no footprint properties: the object's own placed size rounds
      -- to tiles; direction stays its own property
      { kind = "mover", x = 48, y = 16, name = "t2",
        distance = 4, ow = 32, oh = 16, dir = "left" },
      -- clamped to max_tiles (3) each way; a 0 floor is 1
      { kind = "mover", x = 96, y = 16, name = "t3",
        distance = 4, tiles_w = 9, tiles_h = 0, dir = "up" },
      -- the trigger kind still scans (Class MoverTrigger lowercases to
      -- movertrigger; both spellings resolve)
      { kind = "movertrigger", x = 112, y = 16, name = "t4",
        distance = 4, dir = "right" },
      -- dir=up on a wide block: shape and direction are independent
      { kind = "mover", x = 128, y = 16, name = "t5",
        distance = 4, tiles_w = 3, tiles_h = 1, dir = "up" },
      -- dir is case-insensitive
      { kind = "mover", x = 144, y = 16, name = "t6",
        distance = 4, dir = "LEFT" },
      -- a MISSING dir skips the mover (explicit only, like distance)
      { kind = "mover", x = 160, y = 16, name = "t7", distance = 4 },
    },
  }
  local ents = Level.build(fake, config)
  local a, b, c, d = ents.movers[1], ents.movers[2], ents.movers[3],
    ents.movers[4]
  assert_true(a.wt == 3 and a.ht == 2,
    "tiles_w/tiles_h properties size the block (got "
    .. tostring(a.wt) .. "x" .. tostring(a.ht) .. ")")
  assert_true(b.wt == 2 and b.ht == 1,
    "the object's own placed size sizes the block without properties")
  assert_true(c.wt == 3 and c.ht == 1,
    "the footprint clamps to max_tiles each way")
  assert_true(d.mode == "trigger",
    "the movertrigger kind (no underscore) resolves the trigger mode")
  assert_true(#ents.movers == 6,
    "a mover with no `dir` property is skipped (got "
    .. tostring(#ents.movers) .. " of 6)")
  local e, f2 = ents.movers[5], ents.movers[6]
  assert_true(e.dx == 0 and e.dy == -1,
    "dir=up runs the line upward even on a wide block")
  assert_true(f2.dx == -1 and f2.dy == 0,
    "dir=left runs the line leftward (case-insensitive)")
end

-- ==== 2. the auto mover cycles with an exact pause at each end ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local auto = movers(g)
  reset(auto, 0, "go")
  -- run to the far end (192 px at 1 px/step = 192 steps) + one pause
  run_steps(env, 193)
  assert_true(auto.px == auto.len and auto.state == "pause",
    "the auto mover reaches the line's far end and pauses (px "
    .. tostring(auto.px) .. ", state " .. auto.state .. ")")
  assert_true(auto.bx == auto.ox + auto.len,
    "the block sits exactly at the far end")
  -- the pause is exact: still paused one step before it lapses
  run_steps(env, config.mover.pause_steps - 2)
  assert_true(auto.state == "pause", "the far-end pause holds to the step")
  run_steps(env, 1)
  assert_true(auto.state == "go" and auto.dirn == -1,
    "the pause lapses into the return run")
  -- the return is symmetric: back to the home end, same pause, out again
  run_steps(env, 192)
  assert_true(auto.px == 0, "the return reaches the home end")
  run_steps(env, config.mover.pause_steps - 1)
  assert_true(auto.state == "pause", "the home-end pause holds too")
  run_steps(env, 1)
  assert_true(auto.state == "go" and auto.dirn == 1,
    "the auto mover cycles away again after the home pause")
end

-- ==== 3. the rider: carried along, jumping off severs the ride ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  reset(auto, 0, "go")
  -- standing exactly on the block's top face, grounded (the landing
  -- state resolve_y produces: feet ON the face, y = face - height)
  p.x, p.y, p.vx, p.vy = auto.bx + 4, auto.by - p.h, 0, 0
  p.gr = true
  run_steps(env, 1)
  assert_true(p.ride == auto, "the player standing on the block rides it")
  run_steps(env, 20)
  assert_true(math.abs(p.x - (auto.bx + 4)) <= 1,
    "the rider's offset over the block holds while it moves (p.x "
    .. string.format("%.1f", p.x) .. " vs block " .. tostring(auto.bx) .. ")")
  assert_true(p.gr, "the rider stays grounded on the moving block")
  assert_true(p.y == auto.by - p.h,
    "the rider's feet stay on the block's face")
  -- jumping off: the ride severs, and the block's velocity is inherited
  -- (the rider keeps the platform's motion the way ground inertia does)
  local jumped_x = p.x
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 1)
  env.TWANG_TEST.keys_down.x = false
  assert_true(not p.gr or p.vy < 0, "the jump leaves the block")
  run_steps(env, 1)
  assert_true(p.ride ~= auto, "jumping off severs the ride")
  -- the inherited velocity decays under the (deliberately crisp) air
  -- damping across the two world-steps before the sample; the point is
  -- it still carries forward, which the next assert pins
  assert_true(p.vx > 0.1,
    "severing from a moving block inherits its velocity (vx "
    .. string.format("%.2f", p.vx) .. ")")
  assert_true(p.x > jumped_x,
    "the inherited velocity carries the jump along with the block (moved "
    .. string.format("%.1f", p.x - jumped_x) .. " px)")
end

-- ==== 3b. riding like ground: toe-holds, jump-backs, walk-offs ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  reset(auto, 0, "go")
  -- land mid-block (a real fall)
  p.x, p.y, p.vx, p.vy = auto.bx + 8, auto.by - 30, 0, 0
  run_steps(env, 12)
  assert_true(p.ride == auto, "landed for the riding checks")
  -- hanging a TOE over the trailing edge holds the ride (the footing
  -- rule matches normal ground's two-corner stand: the ride breaks
  -- only when the body has FULLY left the block)
  p.x = auto.bx - 3
  run_steps(env, 1)
  assert_true(p.ride == auto and p.gr,
    "a rider hanging a toe over the edge still rides (corner footing)")
  -- a straight-up jump from the MOVING block: the inherited velocity
  -- carries the arc along with the block, so they come down back on it
  p.x = auto.bx + 16
  run_steps(env, 2)
  env.TWANG_TEST.keys_down.x = true
  run_steps(env, 1)
  env.TWANG_TEST.keys_down.x = false
  run_steps(env, 34)
  assert_true(p.ride == auto,
    "a straight-up jump from the moving block lands back on it (offset "
    .. string.format("%.1f", p.x - auto.bx) .. ")")
  -- walking fully off the front severs the ride (and keeps the block's
  -- velocity; the walk cap absorbs it into the walk)
  p.x = auto.bx + auto.bw - 3
  run_steps(env, 1)
  env.TWANG_TEST.keys_down.right = true
  run_steps(env, 10)
  env.TWANG_TEST.keys_down.right = false
  assert_true(p.ride ~= auto,
    "walking fully off the front severs the ride")
end

-- ==== 3d. the edge: stand and ride agree (the block never freezes) ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  reset(auto, 0, "go")
  -- drop onto the block's LEADING edge (their left corner on the face,
  -- their right corner hanging over the void): they land bound and the
  -- block keeps moving under them
  p.x, p.y, p.vx, p.vy = auto.bx + auto.bw - 4, auto.by - 30, 0, 0
  run_steps(env, 30)
  assert_true(p.ride == auto and p.gr and
    math.abs((p.y + p.h) - auto.by) <= 2,
    "an edge landing rides (offset " ..
    string.format("%.1f", p.x - auto.bx) .. ")")
  local bx0 = auto.bx
  run_steps(env, 10)
  assert_true(auto.bx - bx0 == 10 and p.ride == auto,
    "the block keeps moving under an edge-standing rider (moved "
    .. tostring(auto.bx - bx0) .. " px in 10 steps, stall "
    .. tostring(auto.stall_t ~= nil) .. ")")
  -- and NO landing offset can freeze the block: for every drop point
  -- around the edges, once the player has settled, a grounded-on-block
  -- body is always bound, and a body past the face falls clear (the
  -- block's stall must never latch onto them)
  for _, off in ipairs({-8, -4, -1, 0, 8, 16, 24, 30, 32, 34, 36, 40}) do
    local env2 = Harness.boot()
    local g2 = env2.TWANG_TEST.game
    local p2, auto2 = g2.ctx.player, g2.ctx.ents.movers[1]
    reset(auto2, 0, "go")
    p2 = p2
    p2.x, p2.y, p2.vx, p2.vy = auto2.bx + off, auto2.by - 30, 0, 0
    local steps = 0
    while steps < 40 do
      env2.love.update(1/30); env2.love.draw()
      steps = steps + 1
      -- the block must never stall for more than a passing moment
      -- while the player is GROUNDED ON ITS FACE (a bound rider)
      if auto2.stall_t and p2.ride == auto2 then
        assert_true(false, "a bound rider stalled the block at offset "
          .. tostring(off))
        break
      end
    end
    if p2.gr and math.abs((p2.y + p2.h) - auto2.by) <= 2
    and (p2.x + p2.w > auto2.bx and p2.x < auto2.bx + auto2.bw) then
      assert_true(p2.ride == auto2,
        "grounded on the block at drop offset " .. tostring(off)
        .. " means riding")
    end
  end
end

-- ==== 3c. walking and turning on a MOVING lift (the mid-tile face) ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  local lift = select(2, movers(g))
  -- park the auto cycler far down its line so it cannot be under the
  -- lift's columns while this test runs (a falling player would land
  -- on IT instead)
  reset(auto, 150, "go")
  reset(lift, 0, "rest")
  -- a real drop onto the parked lift fires it; ride the descent
  p.x, p.y, p.vx, p.vy = lift.bx + lift.bw / 2, lift.by - 30, 0, 0
  run_steps(env, 14)
  assert_true(p.ride == lift and lift.state == "go",
    "riding the descending lift for the walk checks")
  -- walk RIGHT mid-descent: the offset advances with the walk (no
  -- tile-snap, no sever) — the block's mid-tile top face must never
  -- read as a wall under the rider's own feet
  local off0 = p.x - lift.bx
  env.TWANG_TEST.keys_down.right = true
  local snapped = false
  local prev_off = off0
  for i = 1, 5 do
    env.love.update(1/30); env.love.draw()
    local off = p.x - lift.bx
    if off - prev_off > 4 then
      snapped = true  -- a walk step is at most 3px; more is a snap
    end
    prev_off = off
  end
  env.TWANG_TEST.keys_down.right = false
  assert_true(not snapped and p.ride == lift,
    "walking right on a mid-tile lift advances smoothly (no wall-snap)")
  -- TURN: reverse and walk LEFT back (the walk motor decelerates
  -- through the reversal first) — the offset must come down, riding
  local turn_off = p.x - lift.bx
  env.TWANG_TEST.keys_down.left = true
  run_steps(env, 8)
  env.TWANG_TEST.keys_down.left = false
  assert_true(p.ride == lift and p.vx < 0,
    "turning around on the moving lift walks back the other way (vx "
    .. string.format("%.2f", p.vx) .. ", offset " ..
    string.format("%.1f", p.x - lift.bx) .. ")")
  -- the vertical carry still holds the feet on the face throughout
  assert_true(p.gr and math.abs((p.y + p.h) - lift.by) <= 2,
    "the rider stays glued to the descending face while walking")
end

-- ==== 4. the trigger: landing fires it, staying parked, re-arming ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local lift = select(2, movers(g))
  reset(lift, 0, "rest")
  -- no fire from a nearby stand-in (not on the top face)
  -- clear of the block's CURRENT footprint (whatever the authoring
  -- sizes it to): a player beside it is no landing
  p.x, p.y, p.vx, p.vy = lift.bx + lift.bw + 24, lift.by - 13, 0, 0
  p.gr = true
  run_steps(env, 3)
  assert_true(lift.state == "rest", "the lift ignores a player beside it")
  -- landing on it (grounded, feet reaching the face) fires within a step
  p.x, p.y, p.vx, p.vy = lift.bx + 4, lift.by - 13, 0, 0
  p.gr = true
  run_steps(env, 2)
  assert_true(lift.state == "go",
    "a landing on a parked trigger mover fires it")
  -- it runs the line (96 px = 96 world-steps), pauses at the far end
  -- (30) and returns on its own (96) to park at home after the pause (30)
  run_steps(env, 300)
  assert_true(lift.state == "rest" and lift.px == 0,
    "the lift returns home and parks (state " .. lift.state .. ", px "
    .. tostring(lift.px) .. ")")
  -- the rider never left: stays parked (no infinite ping-pong)
  p.x, p.y, p.vx, p.vy = lift.bx + 4, lift.by - 13, 0, 0
  p.gr = true
  run_steps(env, 10)
  assert_true(lift.state == "rest",
    "a rider who never got off keeps the lift parked")
  -- leaving clears the edge; landing again re-arms and fires
  p.x, p.y, p.vx, p.vy = lift.bx + 60, lift.by - 13, 0, 0
  p.gr = true
  run_steps(env, 2)
  p.x, p.y, p.vx, p.vy = lift.bx + 4, lift.by - 13, 0, 0
  p.gr = true
  run_steps(env, 2)
  assert_true(lift.state == "go",
    "leaving and landing again re-arms the lift")
end

-- ==== 5. the arrow strike: consumed, fires a parked mover ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local lift = select(2, movers(g))
  reset(lift, 0, "rest")
  -- an arrow one step from the block, flying in (pusher-test rig style)
  local a = {
    x = lift.bx + 7, y = lift.by + 7,
    vx = 6, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300,
    kind = "normal", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, a)
  run_steps(env, 4)
  assert_true(not a.active, "the striking arrow is consumed by the block")
  assert_true(lift.state == "go", "the strike fires the parked lift")
  -- a second arrow into the now-moving block is eaten, not re-triggered
  local b = {
    x = lift.bx + 7, y = lift.by + 7,
    vx = 6, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300,
    kind = "normal", traveled = 10,
  }
  table.insert(g.ctx.ents.arrows, b)
  run_steps(env, 6)
  assert_true(not b.active, "arrows into a moving block are eaten too")
end

-- ==== 6. stalls: nothing gets crushed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  -- rig the cycler to descend (dy = 1) toward the pit floor at row 58
  -- (y 928): the lift is a lowering platform, the player stands under it
  auto.dx, auto.dy = 0, 1
  auto.len = 320  -- reach well past the floor line
  reset(auto, 140, "go")  -- start 140 px down (by = 812)
  p.x, p.y, p.vx, p.vy = auto.bx + 4, 58 * 16 - p.h, 0, 0  -- on the floor
  p.gr = true
  run_steps(env, 90)
  -- the block stalled short of the player: its bottom is above their
  -- head, and the player was not crushed (still standing on the floor)
  assert_true(auto.by + auto.bh <= p.y,
    "the lowering block stalls above the player (block bottom "
    .. tostring(auto.by + auto.bh) .. ", player head " .. tostring(p.y) .. ")")
  assert_true(p.y == 58 * 16 - p.h and p.gr,
    "the player under the stalled lift is unharmed and grounded")
  local stalled_by = auto.by
  run_steps(env, 20)
  assert_true(auto.by == stalled_by, "the stall holds while blocked")
  -- the player walks out; the block resumes down to the floor itself
  p.x = p.x + 300
  run_steps(env, 60)
  assert_true(auto.by == 58 * 16 - auto.bh,
    "the block resumes and parks flush on the floor (by "
    .. tostring(auto.by) .. ")")
end

-- ==== 7. off-room movers freeze (the rooms gate) ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local auto = movers(g)
  reset(auto, 0, "go")
  -- an active room that holds the player but excludes the mover's box
  -- (the player grounded inside it, so no room-wipe fires to change the
  -- room and unfreeze the movers)
  local w = g.ctx.world
  w.rooms = { { name = "elsewhere", x = 0, y = 0, w = 64, h = 240, i = 1 } }
  w.active_room = w.rooms[1]
  p.x, p.y, p.vx, p.vy = 40, 14 * 16 - p.h, 0, 0  -- on the room's floor
  p.gr = false
  run_steps(env, 20)
  assert_true(p.gr and w.active_room ~= nil,
    "the test player stands grounded inside the fake room")
  assert_true(auto.px == 0,
    "a mover outside the active room holds its position")
  w.rooms, w.active_room = nil, nil
end

print("mover tests: " .. PASS .. " passed, " .. FAIL .. " failed")
if FAIL > 0 then os.exit(1) end
