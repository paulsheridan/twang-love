-- Entity object resolution tests (deterministic, headless).
--
-- Pins the promise the Tiled docs make: an entity can be authored as a
-- bare Point whose role comes from the object's own `kind` property, the
-- placed tile's kind, or its Class field. In particular the Class field
-- must work whether Tiled wrote the modern "class" key (1.9+) or the
-- legacy "type" key, or a re-save through a newer Tiled silently drops
-- every entity in the map.
--
-- tests/object_kinds_fixture.json places one Point per entity kind, three
-- times over -- Class field, legacy Type field, and a `kind` property --
-- so all three spellings are exercised for the whole vocabulary.
--
-- Usage (from the project root): luajit tests/object_kinds_test.lua

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

local env = Harness.boot("tests/object_kinds_fixture.json")
local tiled = env.require("src.tiled")

-- the vocabulary the loader advertises
local KINDS = {
  "spawn", "key", "lock", "door", "switch", "spring", "winch", "gun",
  "pusher", "updraft", "outdraft", "mover", "mover_trigger",
  "movertrigger", "exit", "checkpoint",
  "archer", "melee", "laser", "rocketeer", "bomber",
}

local map = tiled.load("tests/object_kinds_fixture.json")

-- how many of each kind resolved, and at what y
local by_kind, by_y = {}, {}
for _, o in ipairs(map.objects) do
  by_kind[o.kind] = (by_kind[o.kind] or 0) + 1
  by_y[o.y] = (by_y[o.y] or 0) + 1
end

-- ==== 1. every kind resolves in every spelling ====
for _, k in ipairs(KINDS) do
  assert_true(by_kind[k] == 3,
    "kind '" .. k .. "' resolved from Class/Type/kind-prop (got "
      .. tostring(by_kind[k]) .. "/3, expected 3)")
end

-- the fixture is exactly len(KINDS) x 3 points; nothing else resolved
assert_true(#map.objects == #KINDS * 3,
  "all " .. (#KINDS * 3) .. " fixture points resolved (got " .. #map.objects .. ")")

-- ==== 2. a Point marks the entity's FEET ====
-- The three rows sit at point y = 100/300/500; the loader lifts each by
-- one 16px art cell, so every resolved entity lands at y-16. A wrong
-- offset here is the classic "spawned one tile too low" authoring bug.
assert_true((by_y[100 - tiled.ART] or 0) == #KINDS,
  "Class-field points anchor feet at the point (expected " .. #KINDS
    .. " at y=" .. (100 - tiled.ART) .. ")")
assert_true((by_y[300 - tiled.ART] or 0) == #KINDS,
  "legacy Type-field points anchor feet at the point (expected " .. #KINDS
    .. " at y=" .. (300 - tiled.ART) .. ")")
assert_true((by_y[500 - tiled.ART] or 0) == #KINDS,
  "kind-property points anchor feet at the point (expected " .. #KINDS
    .. " at y=" .. (500 - tiled.ART) .. ")")

print(("object kind tests: %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then os.exit(1) end
