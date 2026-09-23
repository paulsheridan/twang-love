-- Room system tests (deterministic, headless; requires LuaJIT).
--
-- Covers the multi-room system (docs/tiled-format.md "Rooms"; the
-- camera frames in src/camera.lua, the wipe in src/game.lua, the
-- simulation gating in the system update loops), exercised on
-- tests/rooms_fixture.json (three one-screen rooms, open borders,
-- a foreground block in room B, a spawn in room A, an archer in C):
--   1. roomless maps behave exactly as before (clamp rect = world,
--      everything simulates, no wipe)
--   2. the fixture resolves its rooms and the spawn picks room A
--   3. the camera clamps to the active room (one-screen rooms: pinned)
--   4. a hysteresis-checked border crossing starts the wipe; the room
--      switches at full black with the camera snapped into the new room
--   5. per-room foreground fade: only the room you're behind fades
--   6. active-room-only simulation: an off-room enemy freezes mid-state
--      and resumes on re-entry
--   7. rooms smaller than the view centre the clamp range
--
-- Usage (from the project root): luajit tests/rooms_test.lua

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

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

local function pin(env, x, y)
  local p = env.TWANG_TEST.game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

local function room_named(w, name)
  for _, room in ipairs(w.rooms) do
    if room.name == name then return room end
  end
end

-- ==== 1. roomless maps behave exactly as before ====
do
  local env = Harness.boot()
  local w = env.TWANG_TEST.game.ctx.world
  assert_true(w.rooms == nil, "level1 has no rooms")
  local lox, hix, loy, hiy = w:clamp_rect()
  assert_true(lox == 0 and hix == w.px_w - config.view.width
    and loy == 0 and hiy == w.px_h - config.view.height,
    "a roomless map clamps to the whole world")
  assert_true(w:in_room(-50, -50) and w:in_room(9999, 9999),
    "a roomless map simulates everything")
  local p = env.TWANG_TEST.game.ctx.player
  assert_true(w:room_target(p) == false,
    "a roomless map never warrants a room switch")
end

-- ==== 2. the fixture resolves its rooms; the spawn picks room A ====
local env = Harness.boot()
local g = env.TWANG_TEST.game
g:load_level("tests/rooms_fixture.json")
do
  local w = g.ctx.world
  assert_true(w.rooms and #w.rooms == 3, "the fixture has three rooms")
  assert_true(room_named(w, "room_a") ~= nil
    and room_named(w, "room_b") ~= nil and room_named(w, "room_c") ~= nil,
    "the rooms are named")
  assert_true(w.active_room == room_named(w, "room_a"),
    "the spawn resolves the active room")
  assert_true(w.active_room.i == 1, "rooms carry their list index")
end

-- ==== 3. the camera clamps to the active room ====
do
  local w, cam = g.ctx.world, g.ctx.cam
  assert_true(cam.x == 0 and cam.y == 0,
    "the camera sits at room A's origin (one-screen room)")
  w.active_room = room_named(w, "room_c")
  local lox, hix = w:clamp_rect()
  assert_true(lox == 960 and hix == 960,
    "room C clamps the camera to its origin")
  w.active_room = nil
  lox, hix = w:clamp_rect()
  assert_true(lox == 0 and hix == w.px_w - config.view.width,
    "wilderness falls back to whole-map clamping")
  w.active_room = room_named(w, "room_a")
end

-- ==== 4. border crossing: wipe out, switch, wipe in ====
do
  local w = g.ctx.world
  local room_b = room_named(w, "room_b")
  pin(env, 492, 276)  -- centre 16px inside room B (past the hysteresis)
  step(env)
  assert_true(g.room_fade ~= nil and g.room_fade.phase == "out",
    "the crossing starts the wipe")
  assert_true(w.active_room == room_named(w, "room_a"),
    "the room only switches at full black")
  for _ = 1, config.rooms.fade_steps do step(env) end
  assert_true(w.active_room == room_named(w, "room_b"),
    "the switch lands at full black")
  assert_true(g.cam.x == 480 and g.cam.y == 0,
    "the camera snapped into the new room")
  for _ = 1, config.rooms.fade_steps do step(env) end
  assert_true(g.room_fade == nil, "the wipe completes")
  -- walk back: the wipe fires again
  pin(env, 240, 276)
  for _ = 1, config.rooms.fade_steps * 2 + 2 do step(env) end
  assert_true(w.active_room == room_named(w, "room_a")
    and g.room_fade == nil, "crossing back wipes back to room A")
end

-- ==== 5. hysteresis keeps border wiggling from flickering rooms ====
do
  local w = g.ctx.world
  pin(env, 477, 276)  -- centre 3px inside room B: under the hysteresis
  for _ = 1, 5 do step(env) end
  assert_true(g.room_fade == nil
    and w.active_room == room_named(w, "room_a"),
    "a shallow dip across the border does not switch rooms")
end

-- ==== 6. per-room foreground fade independence ====
do
  local w = g.ctx.world
  local a, b = room_named(w, "room_a"), room_named(w, "room_b")
  -- wipe out/in on the teleport plus the ~12-step full fade
  for _ = 1, config.rooms.fade_steps * 2 + 12 do
    pin(env, 724, 128)  -- behind the 3x3 foreground block in room B
    step(env)
  end
  assert_true(w.fg_alpha[b.i] == 0, "room B's foreground fades fully out")
  assert_true(w.fg_alpha[a.i] == nil or w.fg_alpha[a.i] == 1,
    "room A's foreground stays opaque")
  -- and it stays faded while you're away (independence across rooms)
  for _ = 1, config.rooms.fade_steps * 2 + 2 do
    pin(env, 240, 276)
    step(env)
  end
  assert_true(w.fg_alpha[b.i] == 0,
    "room B's foreground does not fade back while you're in room A")
end

-- ==== 7. active-room-only simulation ====
do
  local w = g.ctx.world
  local sentry
  for _, e in ipairs(g.ctx.ents.enemies) do sentry = e end
  assert_true(sentry ~= nil, "the fixture has its archer")
  assert_true(w:room_at(sentry.x + sentry.w/2, sentry.y + sentry.h/2)
    == room_named(w, "room_c"), "the archer lives in room C")
  -- player pinned in room A: the archer must not move a pixel
  pin(env, 240, 276)
  for _ = 1, config.rooms.fade_steps * 2 + 2 do step(env) end
  assert_true(g.ctx.world.active_room == room_named(w, "room_a"),
    "the player is back in room A")
  local frozen = sentry.x
  for _ = 1, 30 do
    pin(env, 240, 276)
    step(env)
  end
  assert_true(sentry.x == frozen,
    "an off-room enemy freezes (it was inside the camera cull margin)")
  -- re-entry: with the player in room C the archer patrols again
  pin(env, 1000, 276)  -- behind the archer: it keeps patrolling
  for _ = 1, config.rooms.fade_steps * 2 + 2 do step(env) end
  assert_true(w.active_room == room_named(w, "room_c"),
    "the player re-enters room C")
  for _ = 1, 30 do
    pin(env, 1000, 276)
    step(env)
  end
  assert_true(sentry.x > frozen,
    "the resumed archer patrols inside its home room")
end

-- ==== 8. rooms smaller than the view centre the clamp range ====
do
  local w = g.ctx.world
  w.rooms = { { name = "tiny", x = 0, y = 0, w = 64, h = 64, i = 1 } }
  w.active_room = w.rooms[1]
  local lox, hix, loy, hiy = w:clamp_rect()
  assert_true(lox == hix and lox == 64/2 - config.view.width/2,
    "a tiny room centres the camera horizontally")
  assert_true(loy == hiy and loy == 64/2 - config.view.height/2,
    "a tiny room centres the camera vertically")
end

print(("room tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
