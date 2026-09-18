-- Winch tests (deterministic, headless; requires LuaJIT).
--
-- Covers the winch (motorized rope reel):
--   1. the level's placed winch loads into ents.winches (grid-snapped,
--      grouped from its name, sprite from the Tiled tile)
--   2. capture: a rope arrow's tip entering the winch's box is consumed
--      and the player starts reeling immediately (any old rope is cut)
--   3. the reel accelerates toward the winch centre; jump does nothing
--   4. release: inside the pass radius the reel lets go and the player
--      is thrown through the centre with at least the minimum speed,
--      out the side opposite the one they hit it from
--   5. firing any arrow cancels a reel in progress
--   6. dying clears the reel
--   7. non-rope arrows pass straight through the winch
--   8. stick grace: movement input is ignored through the reel and for
--      stick_grace steps after release (no accel/damping/walk cap), so
--      the throw's physics play out; input resumes after the grace
--   9. a leftover stuck rope arrow cannot re-grab the player during the
--      grace window (rope_cd covers it); it attaches after it lapses
--  10. the grace ends the moment the thrown player lands
--  11. the throw direction is carried from the entry side: a long reel
--      that overshoots the centre (the ~11% reversal case) still throws
--      forward through the centre, never back the way they came
--
-- Usage (from the project root): luajit tests/winch_test.lua

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

local function run_steps(env, n)
  for _ = 1, n do
    env.love.update(1/30)
    env.love.draw()
  end
end

local function place_player(g, x, y)
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

-- A flying rope arrow for rigging (same shape Arrows.fire builds).
local function rig_rope_shot(g, x, y, vx, vy)
  local a = {
    x = x, y = y, vx = vx, vy = vy,
    active = true, stuck = false, bounced = 0,
    sdx = (vx ~= 0) and (vx / math.abs(vx)) or 0,
    sdy = (vy ~= 0) and (vy / math.abs(vy)) or 0,
    spin = 0, lt = 300, kind = "rope", traveled = 0,
  }
  table.insert(g.ctx.ents.arrows, a)
  return a
end

-- Clears a corridor through tile column 6 and drops a winch into it at
-- (96, 160), centre (104, 168).
local function rig_winch(g)
  local w = g.ctx.world
  for r = 8, 13 do
    if w:tile(6, r) ~= 0 then w:set_tile(6, r, 0) end
  end
  local winch = { x = 96, y = 160, spr = 133 }
  table.insert(g.ctx.ents.winches, winch)
  return w, winch
end

local function winch_centre(w)
  return w.x + 8, w.y + 8
end

local function player_centre(p)
  return p.x + p.w/2, p.y + p.h/2
end

local function centre_dist(g)
  local p = g.ctx.player
  local wx, wy = winch_centre(p.winch.ent)
  local cx, cy = player_centre(p)
  return math.sqrt((wx - cx)^2 + (wy - cy)^2)
end

-- Fires along `angle` by forcing the aim (see rope_test.lua).
local function fire_at(env, g, angle)
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 1)
  g.ctx.player.aim_angle = angle
  kd.z = false
  run_steps(env, 1)
end

-- ==== 1. the placed winches load ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local ws = g.ctx.ents.winches
  assert_true(#ws >= 5, "level1's winch objects loaded (got " .. #ws .. ")")
  local first = ws[1]
  assert_true(first.x == 1072 and first.y == 368,
    "winch_01 snapped to its tile (got " .. first.x .. "," .. first.y .. ")")
  assert_true(first.g == "01", "the name's suffix became the group")
  assert_true(first.spr == 133, "the sprite came from the placed tile")
end

-- ==== 2. capture consumes the rope arrow and starts the pull ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_winch(g)
  -- a normal rope arrow flying into the winch from the left
  rig_rope_shot(g, 80, 168, 8, 0)
  local caught
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then caught = true break end
  end
  assert_true(caught, "the winch caught the rope arrow's tip")
  assert_true(p.winch ~= nil and p.winch.ent.x == 96,
    "the reel references the winch entity")
  assert_true(p.rope == nil, "capturing cut any rope")
  assert_true(#g.ctx.ents.arrows == 0
    or not g.ctx.ents.arrows[1].active,
    "the captured arrow was consumed")
  -- the pull starts right away: the player has begun moving toward it
  run_steps(env, 1)
  local cx0 = p.x
  run_steps(env, 3)
  assert_true(p.x > cx0 or p.y < 198,
    "the player is being pulled toward the winch")
end

-- ==== 3. the reel accelerates; jump does nothing ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_winch(g)
  -- player directly below the winch, standing on the floor
  place_player(g, 100, 212)
  rig_rope_shot(g, 80, 168, 8, 0)
  local caught
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the reel test")
  local d0, d1, d2 = centre_dist(g), nil, nil
  run_steps(env, 1)
  d1 = centre_dist(g)
  run_steps(env, 1)
  d2 = centre_dist(g)
  assert_true(d1 < d0, "the reel closes the distance (" .. d0 .. " -> " .. d1 .. ")")
  assert_true(d2 < d1 - (d0 - d1),
    "the reel accelerates (" .. (d0 - d1) .. " then " .. (d1 - d2) .. " px/step)")
  assert_true(p.rope == nil, "no rope pendulum while winching")
  -- jump is ignored mid-reel
  local kd = env.TWANG_TEST.keys_down
  kd.x = true
  run_steps(env, 1)
  kd.x = false
  run_steps(env, 1)
  assert_true(p.winch ~= nil, "the reel survives a jump press")
  assert_true(p.jbuf == 0, "no jump was buffered mid-reel")
end

-- ==== 4. release: thrown through the centre at (at least) min speed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local wcfg = g.ctx.config.winch
  rig_winch(g)
  place_player(g, 100, 212)  -- below the winch, 50px from its centre
  rig_rope_shot(g, 80, 168, 8, 0)
  local caught
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then caught = true break end
  end
  assert_true(caught, "captured for the release test")
  local below_entry = (p.y + p.h/2) > 168
  assert_true(below_entry, "the player entered from below the winch")
  local released, vy_at_release
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then released = true break end
  end
  assert_true(released, "the reel released inside the pass radius")
  local speed = math.sqrt(p.vx*p.vx + p.vy*p.vy)
  assert_true(speed >= wcfg.min_throw_speed - 0.01,
    "the throw is at least the minimum speed (got " .. speed .. ")")
  vy_at_release = p.vy
  assert_true(vy_at_release < -8,
    "thrown upward, the opposite side from the entry (vy " .. vy_at_release .. ")")
  -- the player passed through the winch's centre and beyond
  local crossed
  for _ = 1, 3 do
    run_steps(env, 1)
    if p.y + p.h/2 < 168 then crossed = true break end
  end
  assert_true(crossed, "the throw carried the player through the centre")
end

-- ==== 5. firing cancels a reel ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_winch(g)
  place_player(g, 100, 212)
  rig_rope_shot(g, 80, 168, 8, 0)
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the fire-cancel test")
  -- mid-reel aim + release: the fire cuts the reel
  local kd = env.TWANG_TEST.keys_down
  kd.z = true
  run_steps(env, 1)
  p.aim_angle = 0.75
  kd.z = false
  run_steps(env, 1)
  assert_true(p.winch == nil, "firing released the reel")
end

-- ==== 6. dying clears the reel ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_winch(g)
  place_player(g, 100, 212)
  rig_rope_shot(g, 80, 168, 8, 0)
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the death test")
  p.hp = 1  -- half a heart left: the hit is fatal
  p.invuln = 0
  local Player = env.require("src.player")
  local fatal = Player.hurt(g.ctx, 0, 0)
  assert_true(fatal, "the hit killed the player")
  assert_true(p.winch == nil, "death cleared the reel")
end

-- ==== 7. non-rope arrows pass straight through ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_winch(g)
  table.insert(g.ctx.ents.arrows, {
    x = 80, y = 168, vx = 8, vy = 0, active = true, stuck = false,
    bounced = 0, sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal",
  })
  run_steps(env, 6)
  assert_true(#g.ctx.ents.arrows == 1 and g.ctx.ents.arrows[1].active,
    "the normal arrow flew through the winch unconsumed")
  assert_true(p.winch == nil, "no reel started")
end

-- ==== 8. stick grace: input ignored through the reel and after release ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local wcfg = g.ctx.config.winch
  rig_winch(g)
  place_player(g, 100, 212)
  rig_rope_shot(g, 80, 168, 8, 0)
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the grace test")
  -- hold right from here on, through the release and past it
  local kd = env.TWANG_TEST.keys_down
  kd.right = true
  local released
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then released = true break end
  end
  assert_true(released, "released for the grace test")
  local vx0 = p.vx
  -- through the whole grace window the held stick does nothing
  for _ = 1, wcfg.stick_grace - 2 do
    run_steps(env, 1)
    assert_true(math.abs(p.vx - vx0) < 0.2,
      ("stick ignored during grace (step %d: vx %.2f vs %.2f)")
        :format(_, p.vx, vx0))
  end
  -- input resumes once the grace lapses
  run_steps(env, 4)
  assert_true(math.abs(p.vx - vx0) > 0.5,
    "movement input works again after the grace (vx " .. vx0 .. " -> " .. p.vx .. ")")
  kd.right = false
end

do
  -- a strong horizontal throw survives the walk cap during the grace:
  -- enter from the side so the throw carries a big horizontal component
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cfg = g.ctx.config.player
  rig_winch(g)
  -- player on the floor, left-below the winch: the pull is diagonal
  place_player(g, 60, 212)
  rig_rope_shot(g, 64, 168, 8, 0)  -- arrow enters the winch from the left
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the cap test")
  local released
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then released = true break end
  end
  assert_true(released, "released for the cap test")
  assert_true(math.abs(p.vx) > cfg.walk_speed + 1,
    "the horizontal throw survives the walk cap (|vx| " .. math.abs(p.vx) .. ")")
  run_steps(env, 3)
  assert_true(math.abs(p.vx) > cfg.walk_speed + 1,
    "still past the walk cap 3 steps after release (|vx| "
      .. math.abs(p.vx) .. ")")
end

-- ==== 9. the grace blocks rope re-attach; it lapses afterwards ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local wcfg = g.ctx.config.winch
  local w = rig_winch(g)
  -- a ceiling for the leftover arrow to embed in (rig_winch cleared it)
  w:set_tile(6, 8, w:tile(0, 14))
  place_player(g, 100, 212)
  rig_rope_shot(g, 80, 168, 8, 0)
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the re-attach test")
  -- a free, terrain-embedded stuck rope arrow appears mid-reel
  table.insert(g.ctx.ents.arrows, {
    x = 104, y = 144, vx = 0, vy = 0, active = true, stuck = true,
    bounced = 0, sdx = 0, sdy = -1, spin = 0, lt = 30000,
    kind = "rope", traveled = 10,
  })
  local released
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then released = true break end
  end
  assert_true(released, "released for the re-attach test")
  assert_true(p.rope == nil,
    "the leftover rope arrow did not re-grab during the grace")
  run_steps(env, wcfg.stick_grace + 3)
  assert_true(p.rope ~= nil,
    "the leftover rope arrow attaches once the grace lapses")
end

-- ==== 10. the grace ends as soon as the throw lands ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local w = g.ctx.world
  rig_winch(g)
  -- player above the winch (row 8 was cleared by rig_winch)
  p.x, p.y, p.vx, p.vy = 100, 132, 0, 0
  -- rope arrow fired straight down into the winch
  rig_rope_shot(g, 104, 138, 0, 8)
  for _ = 1, 8 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "captured for the landing test")
  local released
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then released = true break end
  end
  assert_true(released, "released for the landing test")
  assert_true(p.vy > 0, "the throw carried the player downward (vy "
    .. p.vy .. ")")
  -- hold left from the release on; landing must restore control
  local kd = env.TWANG_TEST.keys_down
  kd.left = true
  local landed
  for _ = 1, 30 do
    run_steps(env, 1)
    if p.gr then landed = true break end
  end
  assert_true(landed, "the thrown player landed")
  assert_true(p.winch_grace == nil,
    "the grace ended the moment the player landed")
  run_steps(env, 3)
  assert_true(p.vx < -1.5,
    "held input steers immediately after landing (vx " .. p.vx .. ")")
  kd.left = false
end

-- ==== 11. the throw direction never inverts on centre overshoot ====
do
  -- The exact geometry that reproduced the ~11% reversal bug on the
  -- real level1 winch: a long approach (reel speed reaches the cap) whose
  -- final reel step carried the player just past the centre, making the
  -- old `rx/dist` release direction point backwards.
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local kd = env.TWANG_TEST.keys_down
  local wx, wy = 1080, 376
  p.x, p.y, p.vx, p.vy = 1074, 438, 0, 0
  kd.c = true; run_steps(env, 1); kd.c = false; run_steps(env, 1)
  kd.z = true; run_steps(env, 1); p.aim_angle = 0.75; kd.z = false
  run_steps(env, 1)
  for _ = 1, 10 do
    run_steps(env, 1)
    if p.winch then break end
  end
  assert_true(p.winch ~= nil, "overshoot case captured")
  local edx, edy = p.winch.dir_x, p.winch.dir_y
  local released, tvx, tvy, tdist
  for _ = 1, 40 do
    run_steps(env, 1)
    if not p.winch then
      released = true
      tvx, tvy = p.vx, p.vy
      local dx, dy = wx - (p.x + p.w/2), wy - (p.y + p.h/2)
      tdist = math.sqrt(dx*dx + dy*dy)
      break
    end
  end
  assert_true(released, "overshoot case released")
  -- the entry side was below: the throw must carry on upward, not back
  assert_true(tvy < 0, "the throw continues forward through the centre (vy "
    .. tvy .. ")")
  assert_true(edx * tvx + edy * tvy > 0,
    "the throw direction matches the entry side (dot "
      .. (edx * tvx + edy * tvy) .. ")")
  assert_true(math.sqrt(tvx*tvx + tvy*tvy) >= g.ctx.config.winch.min_throw_speed - 0.01,
    "the throw keeps its guaranteed minimum speed")
end
do
  -- Bounded sweep: varied sub-pixel entry offsets, long approaches
  -- (reel speed at the cap). No release may point back the way the
  -- player entered; every throw keeps at least the minimum speed.
  local wcfg -- set once
  local bad = 0
  for yi = 3, 7 do
    for off = 2, 14 do
      local env = Harness.boot()
      local g = env.TWANG_TEST.game
      local p = g.ctx.player
      local kd = env.TWANG_TEST.keys_down
      p.x, p.y, p.vx, p.vy = 1064 + off, 468 - yi*6, 0, 0
      kd.c = true; run_steps(env, 1); kd.c = false; run_steps(env, 1)
      kd.z = true; run_steps(env, 1); p.aim_angle = 0.75; kd.z = false
      run_steps(env, 1)
      for _ = 1, 10 do
        run_steps(env, 1)
        if p.winch then break end
      end
      if p.winch then
        local edx, edy = p.winch.dir_x, p.winch.dir_y
        local released
        for _ = 1, 40 do
          run_steps(env, 1)
          if not p.winch then released = true break end
        end
        if released then
          wcfg = g.ctx.config.winch
          local spd = math.sqrt(p.vx^2 + p.vy^2)
          local dot = edx * p.vx + edy * p.vy
          if dot <= 0 or spd < wcfg.min_throw_speed - 0.01 then
            bad = bad + 1
            print(("FAIL (sweep): off=%d yi=%d dot=%.1f spd=%.2f")
              :format(off, yi, dot, spd))
          end
        else
          bad = bad + 1
          print(("FAIL (sweep): off=%d yi=%d never released"):format(off, yi))
        end
      end
    end
  end
  assert_true(bad == 0, "sweep found " .. bad .. " bad releases")
end

print(("winch tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
