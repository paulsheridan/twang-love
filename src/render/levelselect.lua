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

-- 2x-scaled text: chunkier type for the near-fullscreen panel. Even x
-- keeps the scaled glyphs on the pixel grid.
local function big_print(text, x, y)
  love.graphics.push()
  love.graphics.scale(2)
  love.graphics.print(text, x / 2, y / 2)
  love.graphics.pop()
end

return function(ctx)
  local menu = ctx.menu
  local levels = menu.select_levels

  -- near-fullscreen panel: a thin margin around the 480x320 canvas
  local px, py, pw, ph = 12, 8, 456, 304
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)

  -- title: 2x, left-aligned with the rows
  love.graphics.setColor(pcol(10))
  big_print("level select", px + 20, py + 8)

  -- rows: 2x text on a pitch that keeps every entry (plus the help
  -- footer) inside the panel however many levels are listed
  local ry0  = py + 40
  local pitch = math.min(22, math.floor((ph - 40 - 44) / math.max(#levels, 1)))
  for i, entry in ipairs(levels) do
    local y = ry0 + (i - 1) * pitch
    local best = menu.save[entry.file]
    local locked = not menu:level_unlocked(entry)
    local cursor = i == menu.level_sel
    local label = entry.debug and entry.name .. " (debug)" or entry.name
    if best then
      love.graphics.setColor(pcol(cursor and 12 or 7))
      big_print((cursor and ">" or " ") .. label, px + 20, y)
      love.graphics.setColor(pcol(GRADE_COLOURS[best.grade] or 6))
      big_print(best.grade .. " " .. fmt_time(best.time), px + 300, y)
    elseif locked then
      love.graphics.setColor(pcol(5))
      big_print((cursor and ">" or " ") .. label, px + 20, y)
      big_print("locked", px + 300, y)
    else
      love.graphics.setColor(pcol(cursor and 12 or 7))
      big_print((cursor and ">" or " ") .. label, px + 20, y)
    end
  end

  -- footer: 1x, pinned to the panel's bottom edge
  love.graphics.setColor(pcol(12))
  local hy = py + ph - 24
  love.graphics.print("up/down: select  z/x/c: play", px + 20, hy)
  love.graphics.print("esc / back: quit", px + 20, hy + 10)
  love.graphics.setColor(1, 1, 1, 1)
end
