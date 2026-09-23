-- Level-clear results panel, drawn on the 480x320 canvas (pixelated)
-- over the frozen world (see Game:complete_step). Shows the finished
-- run's time, deaths and grade, the recorded best, and the continue
-- controls. The run summary lives on the Game (ctx.menu.result).

local config = require("src.config")
local Palette = require("src.palette")

local pcol = Palette.rgb

local GRADE_COLOURS = { gold = 10, silver = 7, bronze = 9 }

-- Seconds -> "m:ss.d"
local function fmt_time(t)
  return string.format("%d:%04.1f", math.floor(t / 60), t % 60)
end

return function(ctx)
  local menu = ctx.menu
  local r = menu.result
  if not r then return end

  -- centred panel, test-menu styling
  local px, py, pw, ph = 130, 92, 220, 124
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)

  love.graphics.setColor(pcol(10))
  love.graphics.print(r.last and "the end" or "level clear", px + 74, py + 6)

  local lx, rx = px + 16, px + 118
  love.graphics.setColor(pcol(7))
  love.graphics.print("time",   lx, py + 22)
  love.graphics.print("deaths", lx, py + 34)
  love.graphics.print("grade",  lx, py + 46)
  if r.best then
    love.graphics.print("best", lx, py + 58)
  end
  -- values
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(fmt_time(r.time), rx, py + 22)
  love.graphics.print(tostring(r.deaths), rx, py + 34)
  love.graphics.setColor(pcol(GRADE_COLOURS[r.grade] or 7))
  love.graphics.print(r.grade, rx, py + 46)
  if r.best then
    love.graphics.setColor(pcol(6))
    love.graphics.print(fmt_time(r.best.time or r.time) .. " " .. r.best.grade,
      rx, py + 58)
  end

  love.graphics.setColor(pcol(12))
  love.graphics.print("z/x: " .. (r.last and "level select" or "next")
    .. "  c: replay", px + 14, py + 84)
  love.graphics.print("esc: quit", px + 14, py + 96)
  love.graphics.setColor(1, 1, 1, 1)
end
