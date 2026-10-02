-- Launch level-select panel, drawn on the 320x180 canvas (pixelated)
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

  -- near-fullscreen panel: a thin margin around the 320x180 canvas
  local px, py, pw, ph = 6, 6, 308, 168
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)

  -- title, left-aligned with the rows
  love.graphics.setColor(pcol(10))
  love.graphics.print("level select", px + 16, py + 6)

  -- rows: a pitch that keeps every entry (plus the help footer) inside
  -- the panel however many levels are listed
  local ry0  = py + 26
  local pitch = math.min(16, math.floor((ph - 40 - 44) / math.max(#levels, 1)))
  for i, entry in ipairs(levels) do
    local y = ry0 + (i - 1) * pitch
    local best = menu.save[entry.file]
    local locked = not menu:level_unlocked(entry)
    local cursor = i == menu.level_sel
    local label = entry.debug and entry.name .. " (debug)" or entry.name
    if best then
      love.graphics.setColor(pcol(cursor and 12 or 7))
      love.graphics.print((cursor and ">" or " ") .. label, px + 16, y)
      love.graphics.setColor(pcol(GRADE_COLOURS[best.grade] or 6))
      love.graphics.print(best.grade .. " " .. fmt_time(best.time), px + 200, y)
    elseif locked then
      love.graphics.setColor(pcol(5))
      love.graphics.print((cursor and ">" or " ") .. label, px + 16, y)
      love.graphics.print("locked", px + 200, y)
    else
      love.graphics.setColor(pcol(cursor and 12 or 7))
      love.graphics.print((cursor and ">" or " ") .. label, px + 16, y)
    end
  end

  -- footer: pinned to the panel's bottom edge
  love.graphics.setColor(pcol(12))
  local hy = py + ph - 26
  love.graphics.print("up/down: select  z/x/c: play", px + 16, hy)
  love.graphics.print("esc / back: quit", px + 16, hy + 10)
  love.graphics.setColor(1, 1, 1, 1)
end
