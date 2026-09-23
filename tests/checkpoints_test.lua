-- Checkpoint tests (deterministic, headless; requires LuaJIT).
--
-- Covers the checkpoint flags (kind "checkpoint"): touching one sets
-- the respawn point (small poof, re-touch silent), deaths respawn there
-- (full health, key dropped), and maps without checkpoints keep the
-- legacy random-spawn respawn.
--
-- Usage (from the project root): luajit tests/checkpoints_test.lua

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

local function step(env)
  env.love.update(1/30)
  env.love.draw()
end

-- ==== 1. the pinned level has no checkpoints (legacy respawn) ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  assert_true(#g.ctx.ents.checkpoints == 0,
    "the pinned level has no checkpoints")
  assert_true(g.ctx.checkpoint == nil,
    "no checkpoint is set on a checkpointless map")
  g.ctx.die(g.ctx)
  assert_true(g.ctx.player.hp == config.player.hearts * 2,
    "deaths still respawn on a checkpointless map")
end

-- ==== 2. touching a checkpoint sets the respawn ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cp = { x = p.x + tw * 4, y = p.y, spr = 173 }
  table.insert(g.ctx.ents.checkpoints, cp)
  assert_true(g.ctx.checkpoint == nil, "no checkpoint set yet")
  for _ = 1, 4 do
    p.x, p.y, p.vx, p.vy = cp.x, cp.y, 0, 0
    step(env)
  end
  assert_true(g.ctx.checkpoint == cp,
    "touching the flag makes it the respawn point")
  -- carried keys do not drop on the handover (only on death)
  assert_true(#g.ctx.ents.particles <= 8,
    "the handover poof is small (one burst)")
end

-- ==== 3. death respawns at the touched checkpoint ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cp = { x = p.x + tw * 4, y = p.y, spr = 173 }
  table.insert(g.ctx.ents.checkpoints, cp)
  for _ = 1, 4 do
    p.x, p.y, p.vx, p.vy = cp.x, cp.y, 0, 0
    step(env)
  end
  assert_true(g.ctx.checkpoint == cp, "the checkpoint is the respawn")
  -- muster damage, then die: back at the flag, full health
  g.ctx.hurt(g.ctx, 1, 0, 2)
  assert_true(p.hp == 4, "the hit landed before the fatal fall")
  g.ctx.die(g.ctx)
  assert_true(g.deaths == 1, "the death is counted")
  assert_true(p.x >= cp.x - tw and p.x <= cp.x + tw,
    "the player respawns at the checkpoint's column")
  assert_true(p.hp == config.player.hearts * 2,
    "the respawn refills health")
  assert_true(not p.rope and not p.winch, "rope/winch state cleared")
end

-- ==== 4. a later checkpoint takes over ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local cp1 = { x = p.x + tw * 4, y = p.y, spr = 173 }
  local cp2 = { x = p.x + tw * 8, y = p.y, spr = 173 }
  table.insert(g.ctx.ents.checkpoints, cp1)
  table.insert(g.ctx.ents.checkpoints, cp2)
  for _ = 1, 4 do
    p.x, p.y, p.vx, p.vy = cp1.x, cp1.y, 0, 0
    step(env)
  end
  assert_true(g.ctx.checkpoint == cp1, "the first flag takes hold")
  for _ = 1, 4 do
    p.x, p.y, p.vx, p.vy = cp2.x, cp2.y, 0, 0
    step(env)
  end
  assert_true(g.ctx.checkpoint == cp2,
    "touching the later flag re-points the respawn")
  g.ctx.die(g.ctx)
  assert_true(math.abs(p.x - cp2.x) <= tw,
    "death respawns at the latest touched flag")
end

print(("checkpoint tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
