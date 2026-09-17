-- Gated debug logging for the winch reel/throw mechanic.
--
-- Enabled with `config.winch.debug = true`. Each event appends one line
-- to winch_debug.txt (in the LÖVE save directory when running under
-- LÖVE, next to the project when headless) and mirrors it to stdout.
-- Lines are only written while the winch owns the player, so the file
-- stays small; entries sort their fields so output is deterministic.
--
-- Reading a release: dot(entry, throw) < 0 means the throw direction
-- inverted (the overshoot bug this instrumentation was built to hunt).

local config = require("src.config")

local WinchLog = {}

local function fmt(v)
  if type(v) == "number" then return string.format("%.3f", v) end
  return tostring(v)
end

function WinchLog.on()
  local wc = config.winch
  return wc ~= nil and wc.debug or false
end

-- Writes one line: `winch <name> step=<n> key=value ...` (fields sorted).
function WinchLog.log(name, fields)
  if not WinchLog.on() then return end
  local parts = {}
  if fields then
    for k, v in pairs(fields) do
      parts[#parts + 1] = k .. "=" .. (type(v) == "number"
        and string.format("%.3f", v) or tostring(v))
    end
    table.sort(parts)
  end
  local line = "winch " .. name .. " " .. table.concat(parts, " ")
  print(line)
  if love and love.filesystem and love.filesystem.append then
    love.filesystem.append("winch_debug.txt", line .. "\n")
  elseif io then
    local f = io.open("winch_debug.txt", "a")
    if f then
      f:write(line .. "\n")
      f:close()
    end
  end
end

return WinchLog
