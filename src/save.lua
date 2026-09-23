-- Per-level best results, persisted to the LÖVE save directory as a tiny
-- JSON file. Shape: { ["maps/farmhouse.json"] = { time = seconds,
-- grade = "gold"|"silver"|"bronze" } }, keyed by the level's map file so
-- reordering config.levels never invalidates progress.
--
-- Headless harnesses have no love.filesystem: load() then returns an
-- empty table and write() is a no-op, so every code path stays runnable.

local json = require("lib.json")

local Save = {}

local FILE = "save.json"

local function filesystem()
  if love and love.filesystem then return love.filesystem end
  return nil
end

--- Reads the save file; a missing/corrupt file yields an empty table
--- (never nil) so callers can index straight into the result.
function Save.load()
  local fs = filesystem()
  if not fs then return {} end
  local ok, data = pcall(function()
    local raw = fs.read(FILE)
    return raw and json.decode(raw) or {}
  end)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

--- Writes the save; failures are swallowed (a lost best time is not
--- worth taking the game down).
function Save.write(data)
  local fs = filesystem()
  if not fs then return end
  pcall(function() fs.write(FILE, json.encode(data)) end)
end

--- Records a finished run for `file`: best time kept strictly, best
--- grade kept independently (a slow gold run still shows its gold).
function Save.record(data, file, time, grade)
  local best = data[file]
  if not best then
    best = {}
    data[file] = best
  end
  if best.time == nil or time < best.time then best.time = time end
  local rank = { bronze = 1, silver = 2, gold = 3 }
  if best.grade == nil or (rank[grade] or 0) > (rank[best.grade] or 0) then
    best.grade = grade
  end
end

--- Has `file` been cleared at least once? Gates the level select.
function Save.cleared(data, file)
  local best = data[file]
  return best ~= nil and best.time ~= nil
end

return Save
