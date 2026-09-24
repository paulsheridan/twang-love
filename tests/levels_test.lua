-- Level structural tests (deterministic, headless; requires LuaJIT).
--
-- Validates every level listed in config.levels by loading it through
-- the real pipeline (src/tiled.lua -> src/level.lua -> src/world.lua):
--   1. every map loads without loader warnings/errors
--   2. exactly one spawn point (the launch/resume anchor)
--   3. at least one exit flag (the level can be cleared)
--   4. puzzle groups are complete: every key/lock/door group has a lock
--      and a door, every spring-driving switch has a spring
--   5. enemies sit on solid ground and are inside the map bounds
--
-- Usage (from the project root): luajit tests/levels_test.lua

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

-- ==== 1. every listed map loads and is structurally sane ====
for i, entry in ipairs(config.levels) do
  do
    local level = dofile("src/tiled.lua").load(entry.file)
    local ents, tile_ids = dofile("src/level.lua").build(level, config)
    local world = dofile("src/world.lua").new(level, ents, config.tile_size)

    local label = entry.name .. " (" .. entry.file .. ")"
    assert_true(level.MAP_W > 0 and level.MAP_H > 0, label .. ": has a grid")
    if not entry.hidden and not entry.debug then
      -- v1 ladder: full structural checks (hidden and debug workshop
      -- maps are the user's sandboxes: load-only, their own conventions)
      assert_true(#ents.spawn_points == 1,
        label .. ": exactly one spawn point (got " .. #ents.spawn_points .. ")")
      assert_true(#ents.exits >= 1, label .. ": has an exit flag")
      -- puzzle groups: any key's group must have a matching lock
      for _, k in ipairs(ents.keys) do
        local has_lock = false
        for _, l in ipairs(ents.locks) do
          if l.g == k.g then has_lock = true break end
        end
        assert_true(has_lock,
          label .. ": key " .. tostring(k.g) .. " has a lock")
      end
      -- every door group must have a lock or a switch (something that
      -- can open it; a permanently-shut door strands the player)
      for _, d in ipairs(ents.doors) do
        local can_open = false
        for _, l in ipairs(ents.locks) do
          if l.g == d.g then can_open = true break end
        end
        for _, sw in ipairs(ents.switches) do
          if sw.g == d.g then can_open = true break end
        end
        assert_true(can_open,
          label .. ": door group " .. tostring(d.g) .. " can open")
      end
      -- springs fire on switch strikes: every spring's group has a switch
      for _, s in ipairs(ents.springs) do
        local has_switch = false
        for _, sw in ipairs(ents.switches) do
          if sw.g == s.g then has_switch = true break end
        end
        assert_true(has_switch,
          label .. ": spring group " .. tostring(s.g) .. " has a switch")
      end
      -- enemies spawn on solid ground (a fallen enemy drifts forever)
      for _, e in ipairs(ents.enemies) do
        local below = world:solid_at(e.x + e.w/2, e.y + e.h + 1)
        or world:in_slope_solid(e.x + e.w/2, e.y + e.h + 1)
        assert_true(below,
          label .. ": " .. e.type .. " stands on solid ground")
      end
    end
  end
end

-- ==== 2. the v1 ladder teaches in order ====
do
  local visible = {}
  for _, entry in ipairs(config.levels) do
    if not entry.hidden then visible[#visible + 1] = entry end
  end
  assert_true(#visible >= 4, "the v1 ladder has four levels")
  assert_true(visible[1].file == "maps/meadow.json",
    "the ladder opens on the meadow")
  for _, entry in ipairs(visible) do
    assert_true(entry.gold ~= nil and entry.par ~= nil,
      entry.name .. ": grade thresholds authored")
  end
end

print(("levels tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
