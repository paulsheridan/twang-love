-- Characterization harness driver.
--
-- Runs an entry file (legacy or refactored main.lua) headlessly for a fixed
-- number of 30hz sim steps with a deterministic scripted input sequence and
-- dumps periodic state snapshots ("traces"). Run it twice on the legacy
-- entry to confirm determinism, then diff the refactored trace against the
-- legacy one (tests/trace_diff.lua) to prove the refactor changed nothing.
--
-- Usage (from the love2d project root):
--   luajit tests/run.lua tests/legacy_main.lua tests/trace_legacy.txt
--   luajit tests/run.lua main.lua            tests/trace_refactor.txt
-- Requires LuaJIT (LÖVE's Lua 5.1 dialect) for setfenv.

local Harness = dofile("tests/harness.lua")

local entry_path, out_path = arg[1], arg[2]
if not entry_path or not out_path then
  error("usage: luajit tests/run.lua <entry.lua> <trace-out.txt> [from project root]")
end

local TOTAL_STEPS = 900
local DUMP_EVERY = 30

-- ==== scripted input ====
-- Keys are the legacy keymap names. Presses are exactly one step long so
-- they produce a clean btnp edge on that step.
local function script(step)
  local k = {}
  local t = step
  -- walk right with a couple of jumps
  if t >= 10 and t < 100 then k.right = true end
  if t == 40 or t == 80 then k.x = true end
  -- short backtrack
  if t >= 120 and t < 130 then k.left = true end
  if t == 150 then k.x = true end
  -- first aim: hold aim, power up once, release to fire
  if t >= 200 and t < 260 then k.z = true end
  if t == 220 then k.up = true end
  -- advance, single jump
  if t >= 270 and t < 330 then k.right = true end
  if t == 350 then k.x = true end
  -- second aim, power up, fire
  if t >= 400 and t < 460 then k.z = true end
  if t == 420 then k.up = true end
  -- final walk with jumps (long enough to reach the level's edge pits)
  if t >= 500 and t < 750 then k.right = true end
  if t == 510 or t == 540 or t == 600 or t == 640 then k.x = true end
  -- (menu toggle presses at steps 565/585 pause the world mid-walk)
  return k
end

-- Menu-toggle events: [step] = key name, delivered via love.keypressed.
local menu_events = {
  [565] = "m",   -- open the controls panel (pauses the world)
  [585] = "x",   -- press closes the panel again
}

-- ==== deterministic serializer ====
local function ser(v)
  local t = type(v)
  if t == "number" then return string.format("%.6f", v) end
  if t == "boolean" or t == "string" then return tostring(v) end
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(v)
end

-- ==== driver ====
local keys_down = {}
local quit_flag = { false }
local env = Harness.new_env(keys_down, quit_flag)

local chunk = assert(loadfile(entry_path))
setfenv(chunk, env)
chunk()

assert(env.love.load, "entry file defines no love.load")
env.love.load()

local out = {}
local function dump(step)
  local snap = env.TWANG_TEST.trace(step)
  out[#out + 1] = "step " .. step
  out[#out + 1] = ser(snap)
end

for step = 1, TOTAL_STEPS do
  for k in pairs(keys_down) do keys_down[k] = nil end
  for k, v in pairs(script(step)) do keys_down[k] = v end
  local event = menu_events[step]
  if event then env.love.keypressed(event) end
  env.love.update(1 / 30)
  -- exercise the draw path every step too; the strict graphics stubs
  -- turn malformed draw calls (wrong arity/types) into hard errors
  env.love.draw()
  if quit_flag[1] then
    out[#out + 1] = "quit at step " .. step
    break
  end
  if step % DUMP_EVERY == 0 then dump(step) end
end

local f = assert(io.open(out_path, "wb"))
f:write(table.concat(out, "\n") .. "\n")
f:close()
print("wrote " .. #out / 2 .. " snapshots to " .. out_path)
