-- Spring & switch tests (deterministic, headless; requires LuaJIT).
--
-- The level's spring (group 05) sits in a shaft at (1424,224) with its
-- strike switch at (1376,160), same group. Covers:
--   1. the spring's hitbox is the pad band at the tile's bottom: bodies
--      land and stand on the pad surface (spring.y + 8), not the tile top
--   2. a switch strike extends the spring and vaults a player standing
--      on the pad (and does not vault a player standing beside it)
--   3. the struck switch pops back to inactive once the spring resets,
--      and can be shot again
--   4. only switches flagged "phase" flip the level's phase tiles; a
--      spring/door switch strike toggles itself but leaves the blocks
--      alone (no cross-wiring between the puzzle systems)
--   5. a closed door bounces arrows like a sticky wall, and an arrow
--      never embeds in a door that later opens
-- plus the test menu's puzzle toggle:
--   6. disabling the puzzle hides every key, lock and door: they stop
--      being picked up/triggered, doors stop blocking, a carried key
--      drops off, and a switch strike cannot re-close hidden doors
--   7. re-enabling restores the pre-toggle state (carried/unconsumed
--      keys return pickable, triggered doors reopen, consumed stay gone)
--
-- Usage (from the project root): luajit tests/interactables_test.lua

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

local function setup()
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  -- level1's spring/switch pair has been removed from the map; rig a
  -- synthetic pair (entity-owned solidity and strikes need no terrain):
  -- the spring pad standing on the spawn area's floor (row 14 top),
  -- with its group's switch mounted in the sky tile above it
  local spring = { x = 10*16, y = 13*16, g = "springtest", ext = nil,
    spr = g.ctx.tiles.spring, rot = nil }
  local switch = { x = 10*16, y = 12*16, g = "springtest", on = false,
    spr = g.ctx.tiles.switch, rot = nil }
  table.insert(g.ctx.ents.springs, spring)
  table.insert(g.ctx.ents.switches, switch)
  return env, g, spring, switch
end

-- Fires a (synthetic) arrow tip into the switch's tile to strike it.
local function strike(env, g, switch)
  table.insert(g.ctx.ents.arrows, {
    x = switch.x + 4, y = switch.y + 8, vx = 1, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 2, sdy = 0, spin = 0, lt = 300, kind = "normal",
  })
  run_steps(env, 1)
  g.ctx.ents.arrows = {}
end

-- ==== 1. the spring pad: stand on the pad, not the tile top ====
do
  local env, g, spring = setup()
  local p = g.ctx.player
  local pad_top = spring.y + g.ctx.config.springs.pad_height
  -- drop onto the spring from above
  p.x, p.y, p.vx, p.vy = spring.x + 4, spring.y - 48, 0, 0
  run_steps(env, 20)
  assert_true(p.gr, "the player lands on the spring pad")
  assert_true(p.y + p.h == pad_top,
    "the player stands on the pad surface (feet " .. (p.y + p.h)
    .. ", expected " .. pad_top .. ")")
  -- and stays put
  run_steps(env, 10)
  assert_true(p.y + p.h == pad_top, "the player rests on the pad steadily")
end

-- ==== 2. a strike vaults a player standing on the pad ====
do
  local env, g, spring, switch = setup()
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = spring.x + 4, spring.y - 48, 0, 0
  run_steps(env, 20)  -- landed on the pad
  strike(env, g, switch)
  assert_true(switch.on, "the strike turns the switch on")
  local ext = g.ctx.config.springs.extension_frames
  assert_true(spring.ext == ext - 1,
    "the strike extends the spring (ext " .. tostring(spring.ext) .. ")")
  assert_true(p.vy == g.ctx.config.springs.launch_velocity,
    "the player on the pad is vaulted (vy " .. tostring(p.vy) .. ")")
  assert_true(not p.gr, "the vaulted player is airborne")
  -- a player standing beside the spring (on the shaft floor, 8px below
  -- the pad surface) is not vaulted
  p.x, p.y, p.vx, p.vy = spring.x - 12, spring.y + 16 - p.h, 0, 0
  run_steps(env, 4)
  assert_true(p.gr and p.y + p.h == spring.y + 16,
    "the player beside the spring stands on the shaft floor (feet "
    .. (p.y + p.h) .. ")")
  strike(env, g, switch)
  assert_true(p.vy == 0, "a player beside the spring is not vaulted")
end

-- ==== 3. the switch pops back out when the spring resets ====
do
  local env, g, spring, switch = setup()
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = spring.x + 4, spring.y - 48, 0, 0
  run_steps(env, 20)
  strike(env, g, switch)
  assert_true(switch.on, "the switch is on right after the strike")
  local ext = g.ctx.config.springs.extension_frames
  run_steps(env, ext - 2)
  assert_true(switch.on, "the switch stays on while the spring is extended")
  run_steps(env, 3)
  assert_true(spring.ext == nil, "the spring resets after its extension")
  assert_true(not switch.on, "the switch pops back to inactive")
  -- and can be shot again
  strike(env, g, switch)
  assert_true(switch.on and spring.ext == ext - 1,
    "the reset switch strikes again (re-extends the spring)")
end

-- ==== 4. only "phase" switches flip the phase tiles ====
do
  local env, g, spring, switch = setup()
  local w = g.ctx.world
  -- a spare non-phase switch (strikes of ANY switch used to flip phase)
  local other = g.ctx.ents.switches[1]
  assert_true(not other.phase, "a spring/door switch carries no phase flag")
  -- an empty, object-free cell: (8,8) in level1's upper-left sky region
  local c, r = 8, 8
  local px, py = c*16 + 8, r*16 + 8
  w:set_tile(c, r, 135)  -- the tileset's designated phase tile
  assert_true(w:is_phase(135), "tile 135 is flagged as a phase tile")
  assert_true(w.phase_solid, "phase tiles start solid on level load")
  assert_true(w:solid_at(px, py),
    "a placed phase tile blocks bodies while solid")
  -- striking a non-phase switch: it toggles, but the blocks stay put
  strike(env, g, other)
  assert_true(other.on, "the non-phase switch toggles on when struck")
  assert_true(w.phase_solid,
    "a non-phase switch strike leaves the phase tiles solid")
  -- the phase switch (the level's g=pform switches carry the flag)
  local pswitch
  for _, s in ipairs(g.ctx.ents.switches) do
    if s.phase then pswitch = s break end
  end
  assert_true(pswitch ~= nil, "the level has a phase switch")
  -- first strike: the phase tiles dissolve
  strike(env, g, pswitch)
  assert_true(not w.phase_solid, "a phase switch strike dissolves the tiles")
  assert_true(not w:solid_at(px, py),
    "a non-solid phase tile no longer blocks bodies")
  assert_true(not w:solid_for_arrow(px, py),
    "arrows fly through a non-solid phase tile")
  -- second strike: the tiles restore
  strike(env, g, pswitch)
  assert_true(w.phase_solid and w:solid_at(px, py),
    "a second phase switch strike re-solidifies the tiles")
end

-- ==== 5. a closed door bounces arrows; none embeds when it opens ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local w = g.ctx.world
  -- a door object in an empty sky cell (8,10): solidity and bounciness
  -- are the door object's alone, so this needs no map terrain
  local c, r = 8, 10
  local door = { tc = c, tr = r, x = c*16, y = r*16, open = false, g = "t" }
  table.insert(g.ctx.ents.doors, door)
  local px, py = c*16 + 8, r*16 + 8
  assert_true(w:solid_at(px, py), "a closed door owns a solid tile")
  assert_true(w:sticky_at(px, py),
    "a closed door bounces arrows like a sticky wall")
  -- an arrow flying into the closed door: reflected, never stuck
  local a = {
    x = c*16 - 2, y = r*16 + 8, vx = 4, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal",
  }
  table.insert(g.ctx.ents.arrows, a)
  run_steps(env, 1)
  assert_true(a.bounced == 1 and a.vx == -4,
    "the arrow bounced off the closed door (vx " .. a.vx .. ")")
  assert_true(not a.stuck, "the arrow did not embed in the door")
  -- opening the door: nothing is left hanging in the doorway
  door.open = true
  assert_true(not w:solid_at(px, py), "an open door no longer blocks")
  assert_true(not w:sticky_at(px, py),
    "an open door no longer bounces arrows")
  run_steps(env, 6)
  assert_true(not (a.active and a.stuck),
    "no arrow ends up stuck where the door used to be")
  for _, ar in ipairs(g.ctx.ents.arrows) do
    assert_true(not (ar.stuck
      and math.floor(ar.x/16) == c and math.floor(ar.y/16) == r),
      "no stuck arrow remains inside the opened door's tile")
  end
end

-- ==== 6. disabling the puzzle hides keys, locks and doors ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local w, ents, p = g.ctx.world, g.ctx.ents, g.ctx.player
  local Interactables = dofile("src/interactables.lua")
  local k1, k2 = ents.keys[1], ents.keys[2]
  local lock1, lock3 = ents.locks[1], ents.locks[3]
  local door1 = ents.doors[1]  -- group 01, closed on load
  assert_true(door1.g == "01", "door 1 belongs to the key-1 group")
  -- someone carries key 1; an arrow carries key 2
  k1.taken, p.key = true, k1
  local arrow = { x = k2.x, y = k2.y, key = k2, active = true,
    stuck = false, lt = 300, vx = 0, vy = 0, sdx = 1, sdy = 0 }
  table.insert(ents.arrows, arrow)
  -- door group 03 stands open: its lock was already triggered pre-toggle
  Interactables.trigger_lock(ents, lock3)
  -- remember the exact pre-toggle state of every piece
  local pre_open, pre_triggered = {}, {}
  for _, d in ipairs(ents.doors) do pre_open[d] = d.open end
  for _, l in ipairs(ents.locks) do pre_triggered[l] = l.triggered end

  g:toggle_puzzle()
  assert_true(g.settings.no_puzzle, "the toggle turns the puzzle off")
  for _, k in ipairs(ents.keys) do
    assert_true(k.taken, "every key is marked taken while hidden")
  end
  for _, l in ipairs(ents.locks) do
    assert_true(l.triggered, "every lock is marked triggered while hidden")
  end
  for _, d in ipairs(ents.doors) do
    assert_true(d.open, "every door stands open while hidden")
    assert_true(d.disabled, "every door carries the disabled flag")
  end
  local px, py = door1.x + 8, door1.y + 8
  assert_true(not w:solid_at(px, py),
    "a hidden door's tile no longer blocks bodies")
  assert_true(not w:solid_for_arrow(px, py),
    "arrows fly through a hidden door")
  assert_true(p.key == nil, "a carried key drops off the player")
  assert_true(arrow.key == nil, "a carried key drops off its arrow")

  -- the player standing on a hidden key's tile cannot pick it up
  for _ = 1, 3 do
    p.x, p.y, p.vx, p.vy = k2.x - 4, k2.y - 4, 0, 0
    run_steps(env, 1)
  end
  assert_true(p.key == nil, "a hidden key is never picked up")

  -- a switch strike cannot re-close hidden doors (group 04 is
  -- switch-driven; its doors stay open while the puzzle is hidden)
  local door7
  for _, d in ipairs(ents.doors) do
    if d.g == "04" and d.y == 208 then door7 = d end
  end
  assert_true(door7 ~= nil, "a group-04 door exists")
  local sw4 = ents.switches[1]
  assert_true(sw4.g == "04", "switch 1 drives group 04")
  table.insert(ents.arrows, {
    x = sw4.x + 4, y = sw4.y + 8, vx = 1, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 2, sdy = 0, spin = 0, lt = 300, kind = "normal",
  })
  run_steps(env, 1)
  ents.arrows = {}
  assert_true(sw4.on, "the strike toggles the switch on")
  assert_true(door7.open, "a hidden switch-driven door stays open")

  g:toggle_puzzle()  -- back on
  assert_true(not g.settings.no_puzzle, "the toggle turns the puzzle on")
  for _, d in ipairs(ents.doors) do
    assert_true(d.open == pre_open[d] and d.disabled == nil,
      "each door restores its pre-toggle state")
  end
  for _, l in ipairs(ents.locks) do
    assert_true(l.triggered == pre_triggered[l],
      "each lock restores its pre-toggle state")
  end
  assert_true(not k1.taken and k1.used == nil,
    "the formerly carried key returns to the world")
  assert_true(not k2.taken, "an unconsumed key becomes pickable again")
  assert_true(w:solid_at(px, py), "the restored door blocks bodies again")
  -- the re-armed key is picked up again
  for _ = 1, 3 do
    p.x, p.y, p.vx, p.vy = k2.x - 4, k2.y - 4, 0, 0
    run_steps(env, 1)
  end
  assert_true(p.key == k2, "the restored key is picked up again")
end

-- ==== 7. a key consumed before the toggle stays consumed ====
do
  local env = Harness.boot()
  local g = env.TWANG_TEST.game
  local Interactables = dofile("src/interactables.lua")
  local ents = g.ctx.ents
  local k = ents.keys[3]
  local lock = ents.locks[3]
  k.taken, k.used = true, true  -- consumed by its lock earlier
  Interactables.trigger_lock(ents, lock)
  g:toggle_puzzle()
  g:toggle_puzzle()
  assert_true(k.taken and k.used,
    "a consumed key does not come back when the puzzle is re-enabled")
end

print(("interactables tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
