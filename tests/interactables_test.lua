-- Spring & switch tests (deterministic, headless; requires LuaJIT).
--
-- The level's spring (group 05) sits in a shaft at (712,112) with its
-- strike switch at (688,80), same group. Covers:
--   1. the spring's hitbox is the pad band at the tile's bottom: bodies
--      land and stand on the pad surface (spring.y + 4), not the tile top
--   2. a switch strike extends the spring and vaults a player standing
--      on the pad (and does not vault a player standing beside it)
--   3. the struck switch pops back to inactive once the spring resets,
--      and can be shot again
--   4. every switch strike toggles the switch (on<->off), and flips the
--      level's phase tiles solid<->non-solid together
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
  local spring, switch
  for _, s in ipairs(g.ctx.ents.springs) do spring = s end
  for _, s in ipairs(g.ctx.ents.switches) do
    if s.g == spring.g then switch = s end
  end
  return env, g, spring, switch
end

-- Fires a (synthetic) arrow tip into the switch's tile to strike it.
local function strike(env, g, switch)
  table.insert(g.ctx.ents.arrows, {
    x = switch.x + 2, y = switch.y + 4, vx = 0.5, vy = 0,
    active = true, stuck = false, bounced = 0,
    sdx = 1, sdy = 0, spin = 0, lt = 300, kind = "normal",
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
  p.x, p.y, p.vx, p.vy = spring.x + 2, spring.y - 24, 0, 0
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
  p.x, p.y, p.vx, p.vy = spring.x + 2, spring.y - 24, 0, 0
  run_steps(env, 20)  -- landed on the pad
  strike(env, g, switch)
  assert_true(switch.on, "the strike turns the switch on")
  local ext = g.ctx.config.springs.extension_frames
  assert_true(spring.ext == ext - 1,
    "the strike extends the spring (ext " .. tostring(spring.ext) .. ")")
  assert_true(p.vy == g.ctx.config.springs.launch_velocity,
    "the player on the pad is vaulted (vy " .. tostring(p.vy) .. ")")
  assert_true(not p.gr, "the vaulted player is airborne")
  -- a player standing beside the spring (on the shaft floor, 4px below
  -- the pad surface) is not vaulted
  p.x, p.y, p.vx, p.vy = spring.x - 6, spring.y + 8 - p.h, 0, 0
  run_steps(env, 4)
  assert_true(p.gr and p.y + p.h == spring.y + 8,
    "the player beside the spring stands on the shaft floor (feet "
    .. (p.y + p.h) .. ")")
  strike(env, g, switch)
  assert_true(p.vy == 0, "a player beside the spring is not vaulted")
end

-- ==== 3. the switch pops back out when the spring resets ====
do
  local env, g, spring, switch = setup()
  local p = g.ctx.player
  p.x, p.y, p.vx, p.vy = spring.x + 2, spring.y - 24, 0, 0
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

-- ==== 4. switch strikes toggle the switch and flip the phase tiles ====
do
  local env, g, spring, switch = setup()
  local w = g.ctx.world
  -- a spare switch to strike (strikes of ANY switch flip phase tiles)
  local any_switch = g.ctx.ents.switches[1]
  -- an empty, object-free cell: (8,8) in level1's upper-left sky region
  local c, r = 8, 8
  local px, py = c*8 + 4, r*8 + 4
  w:set_tile(c, r, 135)  -- the tileset's designated phase tile
  assert_true(w:is_phase(135), "tile 135 is flagged as a phase tile")
  assert_true(w.phase_solid, "phase tiles start solid on level load")
  assert_true(w:solid_at(px, py),
    "a placed phase tile blocks bodies while solid")
  -- first strike: the switch turns on, phase tiles dissolve
  strike(env, g, any_switch)
  assert_true(not w.phase_solid, "a switch strike dissolves the phase tiles")
  assert_true(not w:solid_at(px, py),
    "a non-solid phase tile no longer blocks bodies")
  assert_true(not w:solid_for_arrow(px, py),
    "arrows fly through a non-solid phase tile")
  -- second strike: the switch turns off, phase tiles restore
  strike(env, g, any_switch)
  assert_true(not switch.on and not any_switch.on,
    "a second strike toggles the struck switch back off")
  assert_true(w.phase_solid and w:solid_at(px, py),
    "a second strike re-solidifies the phase tiles")
end

print(("interactables tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
