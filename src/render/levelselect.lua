-- Launch level-select panel, drawn on the 480x320 canvas (pixelated)
-- over the paused preloaded level (see Game:select_step). Rows come
-- from config.levels; the cursor lives on the Game (ctx.menu.level_sel).
-- The headless harness skips this screen entirely (boots into play), so
-- these draws only run in a real LÖVE session.

local config = require("src.config")
local Palette = require("src.palette")

local pcol = Palette.rgb

return function(ctx)
  local menu = ctx.menu
  local levels = config.levels

  -- centred panel, test-menu styling
  local px, py, pw, ph = 140, 106, 200, 108
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", px + 0.5, py + 0.5, pw - 1, ph - 1)

  love.graphics.setColor(pcol(10))
  love.graphics.print("level select", px + 66, py + 6)

  for i, entry in ipairs(levels) do
    local y = py + 22 + (i - 1) * 12
    love.graphics.setColor(pcol(i == menu.level_sel and 12 or 7))
    love.graphics.print((i == menu.level_sel and ">" or " ") .. entry.name,
      px + 14, y)
  end

  love.graphics.setColor(pcol(12))
  local hy = py + 22 + #levels * 12 + 2
  love.graphics.print("up/down: select  z/x/c: play", px + 14, hy)
  love.graphics.print("esc / back: quit", px + 14, hy + 10)
  love.graphics.setColor(1, 1, 1, 1)
end
