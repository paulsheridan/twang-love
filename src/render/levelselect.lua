-- Launch level-select panel, drawn on the 480x320 canvas (pixelated)
-- over the paused preloaded level (see Game:select_step). Rows come
-- from Game.select_levels; the cursor lives on the Game
-- (ctx.menu.level_sel). Cleared levels show their best grade/time;
-- levels not yet cleared (previous one uncleared) show locked. The
-- headless harness skips this screen entirely (boots into play), so
-- these draws only run in a real LÖVE session.

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
  local levels = menu.select_levels

  -- centred panel, test-menu styling; height scales with the row count
  local px, py, pw = 140, 106, 200
  local ph = 30 + #levels * 12 + 20
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)

  love.graphics.setColor(pcol(10))
  love.graphics.print("level select", px + 66, py + 6)

  for i, entry in ipairs(levels) do
    local y = py + 22 + (i - 1) * 12
    local best = menu.save[entry.file]
    local locked = not menu:level_unlocked(entry)
    local cursor = i == menu.level_sel
    local label = entry.debug and entry.name .. " (debug)" or entry.name
    if best then
      love.graphics.setColor(pcol(cursor and 12 or 7))
      love.graphics.print((cursor and ">" or " ") .. label, px + 14, y)
      love.graphics.setColor(pcol(GRADE_COLOURS[best.grade] or 6))
      love.graphics.print(best.grade .. " " .. fmt_time(best.time),
        px + 118, y)
    elseif locked then
      love.graphics.setColor(pcol(5))
      love.graphics.print((cursor and ">" or " ") .. label, px + 14, y)
      love.graphics.print("locked", px + 118, y)
    else
      love.graphics.setColor(pcol(cursor and 12 or 7))
      love.graphics.print((cursor and ">" or " ") .. label, px + 14, y)
    end
  end

  love.graphics.setColor(pcol(12))
  local hy = py + 22 + #levels * 12 + 2
  love.graphics.print("up/down: select  z/x/c: play", px + 14, hy)
  love.graphics.print("esc / back: quit", px + 14, hy + 10)
  love.graphics.setColor(1, 1, 1, 1)
end
