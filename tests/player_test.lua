-- Player health tests (deterministic, headless; requires LuaJIT).
--
-- Covers the hearts system (health in half-hearts, half a heart lost
-- per hit):
--   1. a melee touch costs half a heart and grants i-frames: further
--      contact is shielded until the invulnerability lapses
--   2. an enemy arrow hit costs half a heart
--   3. the last half-heart lost is fatal: death, respawn with a full
--      refill, arrows cleared
--   4. falling off the world is an instant death and refills health
--   5. jump corner forgiveness: a one-corner head clip slides around
--      the ledge instead of killing the jump; overhangs still bump
-- plus the hit-feedback behaviours:
--   6. a landed hit sprays blood opposite the impact (arrows and melee)
--   7. Particles.blood adds the given base velocity to every particle
--   8. a hit enemy arrow rests at the impact point, then vanishes
--   9. a fast enemy arrow cannot tunnel through the player's box
--
-- Usage (from the project root): luajit tests/player_test.lua

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

local function place_player(game, x, y)
  local p = game.ctx.player
  p.x, p.y, p.vx, p.vy = x, y, 0, 0
end

local function max_hp() return 6 end  -- 3 hearts * 2 half-hearts

-- ==== 1. melee contact drains half a heart per invulnerability window ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local melee
  for _, e in ipairs(g.ctx.ents.enemies) do
    if e.type == "melee" then melee = e break end
  end
  -- stand the player in the melee's path and pin the melee overlapping
  -- it every step (resolve happens inside update; the pin guarantees
  -- contact regardless of the patrol)
  local hp_seen = {}
  for step = 1, 250 do
    p.x, p.y, p.vx, p.vy = 660, 212, 0, 0
    melee.x, melee.y, melee.vx, melee.vy = 652, 208, 0, 0
    env.love.update(1/30)
    env.love.draw()
    if p.hp ~= hp_seen[#hp_seen] then
      hp_seen[#hp_seen + 1] = p.hp
      hp_seen["at" .. #hp_seen] = step
    end
    if p.hp == max_hp() and #hp_seen >= max_hp() then break end  -- died and respawned
  end
  -- drained 6 -> 5 -> 4 -> ... one half-heart per invulnerability window
  assert_true(#hp_seen >= 3,
    "melee contact drains health one half-heart at a time (saw "
    .. #hp_seen .. " values)")
  assert_true(hp_seen[1] == 5 and hp_seen[2] == 4,
    "health goes 6 -> 5 -> 4 under repeated contact")
  local invuln = g.ctx.config.player.invuln_steps
  assert_true(hp_seen.at2 - hp_seen.at1 >= invuln,
    "the second half-heart is only lost after i-frames lapse (gap "
    .. (hp_seen.at2 - hp_seen.at1) .. ")")
end

-- ==== 2. an enemy arrow hit costs half a heart ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 720, 148)
  -- dart straight at the player (slow enough to land inside the box)
  table.insert(g.ctx.ents.e_arrows, {
    x = 704, y = 154, vx = 8, vy = 0, active = true,
  })
  run_steps(env, 6)
  assert_true(p.hp == max_hp() - 1,
    "an arrow hit costs half a heart (hp now " .. tostring(p.hp) .. ")")
  assert_true(p.invuln > 0, "the hit grants invulnerability frames")
end

-- ==== 6. a landed hit sprays blood opposite the impact ====
do
  -- arrow travelling left: the spray must fly back to the right (+x)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 720, 148)
  table.insert(g.ctx.ents.e_arrows, {
    x = 736, y = 154, vx = -8, vy = 0, active = true,
  })
  local hit_seen = false
  for _ = 1, 6 do
    run_steps(env, 1)
    if p.hp == max_hp() - 1 then hit_seen = true break end
  end
  assert_true(hit_seen, "the leftward arrow hit the player")
  local parts = g.ctx.ents.particles
  local blood_count = g.ctx.config.particles.blood_count
  assert_true(#parts >= blood_count,
    "an arrow hit sprays blood (" .. #parts .. " particles)")
  local all_rightward = true
  for _, pt in ipairs(parts) do
    if pt.vx <= 0 then all_rightward = false end
  end
  assert_true(all_rightward,
    "blood sprays opposite the arrow's travel (back to the right)")
end

do
  -- melee contact: the spray must fly away from the attacker (-x here)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  local melee
  for _, e in ipairs(g.ctx.ents.enemies) do
    if e.type == "melee" then melee = e break end
  end
  p.x, p.y, p.vx, p.vy = 660, 212, 0, 0
  melee.x, melee.y, melee.vx, melee.vy = 652, 208, 0, 0
  run_steps(env, 1)
  local parts = g.ctx.ents.particles
  local blood_count = g.ctx.config.particles.blood_count
  assert_true(p.hp == max_hp() - 1, "the melee touch landed")
  assert_true(#parts >= blood_count,
    "a melee hit sprays blood (" .. #parts .. " particles)")
  local all_leftward = true
  for _, pt in ipairs(parts) do
    if pt.vx >= 0 then all_leftward = false end
  end
  assert_true(all_leftward,
    "blood sprays away from the melee attacker (to the left)")
end

-- ==== 7. Particles.blood adds the base velocity to every particle ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local Particles = dofile("src/particles.lua")
  local cfg = g.ctx.config.particles
  local before = #g.ctx.ents.particles
  Particles.blood(g.ctx.ents, 100, 100, 8, 0, 10, -5)
  local parts = g.ctx.ents.particles
  assert_true(#parts == before + cfg.blood_count, "blood() adds particles")
  local ok = true
  for i = before + 1, #parts do
    local pt = parts[i]
    -- pure spray along -x is vx in [-4.1, -0.99]; with +10 base every
    -- particle must land well above zero
    if not (pt.vx > 5 and pt.vy < -3.5) then ok = false end
  end
  assert_true(ok, "every particle inherited the base velocity")
end

-- ==== 8. a hit enemy arrow rests at the impact point, then vanishes ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 720, 148)
  table.insert(g.ctx.ents.e_arrows, {
    x = 704, y = 154, vx = 8, vy = 0, active = true,
  })
  run_steps(env, 2)  -- the arrow reaches the player on the second step
  assert_true(p.hp == max_hp() - 1, "the arrow hit (hp " .. p.hp .. ")")
  assert_true(#g.ctx.ents.e_arrows == 1,
    "the hit arrow is not removed immediately")
  local a = g.ctx.ents.e_arrows[1]
  local fx, fy = a.x, a.y
  run_steps(env, 2)
  assert_true(#g.ctx.ents.e_arrows == 1 and a.x == fx and a.y == fy,
    "the arrow stays frozen at the impact point")
  local stick = g.ctx.config.arrows.player_stick_frames
  run_steps(env, stick + 1)
  assert_true(#g.ctx.ents.e_arrows == 0,
    "the arrow vanishes after the stick window lapses")
end

-- ==== 9. a fast enemy arrow cannot tunnel through the player's box ====
-- The dart's per-step move (~16.9px) exceeds the box's width (8px): its
-- endpoint lands past the player, but the substep samples land inside.
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  place_player(g, 720, 148)
  table.insert(g.ctx.ents.e_arrows, {
    x = 712, y = 154, vx = 16.5, vy = 0, active = true,
  })
  run_steps(env, 3)
  assert_true(p.hp == max_hp() - 1,
    "a fast dart that overflies the box edge still connects (hp "
    .. tostring(p.hp) .. ")")
end

-- ==== 3. the last half-heart lost is fatal and refills on respawn ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.hp = 1
  place_player(g, 720, 148)
  local before_x, before_y = p.x, p.y
  table.insert(g.ctx.ents.e_arrows, {
    x = 704, y = 154, vx = 8, vy = 0, active = true,
  })
  run_steps(env, 6)
  assert_true(p.hp == max_hp(), "respawn refills health to full")
  assert_true(p.invuln == 0, "respawn clears invulnerability")
  assert_true(p.x ~= before_x or p.y ~= before_y,
    "the fatal hit respawned the player")
end

-- ==== 4. falling off the world is instant death ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  p.hp = 2
  p.y = g.ctx.world.px_h + 80
  run_steps(env, 3)
  assert_true(p.hp == max_hp(),
    "the void kills outright and respawns at full health")
end

-- ==== 5. jump corner forgiveness ====
-- Rigs a ceiling tile at (6,9): x 96..111, y 144..159. The player (8px
-- wide) placed at x=90 has only its right head corner inside the tile's
-- column, so rising into row 9 clips the ledge's edge corner.
local function rig_ledge(g)
  local w = g.ctx.world
  local solid_id = w:tile(0, 14)  -- the spawn-area wall/floor tile id
  w:set_tile(6, 9, solid_id)
  return w
end

do
  -- one-corner clip: the player slides around the ledge and keeps the
  -- full jump height (velocity preserved, never bumped)
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  place_player(g, 90, 160)
  p.gr = false
  p.vy = -6
  run_steps(env, 1)
  assert_true(p.vy < 0, "the corner clip did not kill the jump (vy "
    .. p.vy .. ")")
  assert_true(p.x == 88, "the player slid around the corner (x "
    .. p.x .. ")")
  run_steps(env, 8)
  assert_true(p.y < 144, "the jump reached its full height above the "
    .. "ledge (y " .. p.y .. ")")
end
do
  -- an overhang covering both head corners still bumps normally
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  place_player(g, 97, 160)  -- box 97..104: both corners under the ledge
  p.gr = false
  p.vy = -4
  run_steps(env, 1)
  assert_true(p.vy == 0, "a covered head bump zeroes the velocity")
  assert_true(p.y == 160, "the bump snaps the player below the ledge")
end
do
  -- a slide deeper than the nudge cap refuses and bumps
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local p = g.ctx.player
  rig_ledge(g)
  g.ctx.config.player.corner_nudge_px = 2  -- this clip needs a 4px slide
  place_player(g, 92, 160)  -- box 92..99: right corner clips 4px deep
  p.gr = false
  p.vy = -4
  run_steps(env, 1)
  assert_true(p.vy == 0, "a slide past the nudge cap bumps instead")
  assert_true(p.y == 160, "the refused nudge snapped below the ledge")
end

print(("player tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
