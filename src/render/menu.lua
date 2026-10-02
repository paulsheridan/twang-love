-- Test menu panel, drawn on the 320x180 canvas (pixelated). Five test
-- toggles (see Game:menu_step): puzzle pieces hidden, invincibility and
-- enemies on/off, special arrows (bomb/spirit) hidden from the swap
-- cycle, unlock-all levels (progress gating off), plus a row that
-- returns to the launch level select. Selection state lives on the
-- Game (ctx.menu).
--
-- The panel is near-fullscreen: at this canvas size the default font's
-- row labels need the width, so the box hugs the edges and the text
-- hangs off a narrow left gutter.

local config = require("src.config")
local Palette = require("src.palette")

local pcol = Palette.rgb

return function(ctx)
  local menu = ctx.menu
  local settings = menu.settings

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 8, 6, 304, 168)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", 8.5, 6.5, 303, 167)

  love.graphics.setColor(pcol(10))
  love.graphics.print("test menu", 26, 12)

  local rows = {
    { "doors/keys/locks hidden", settings.no_puzzle },
    { "invincibility",           settings.invincible },
    { "enemies enabled",         config.enemies.enabled },
    { "special arrows hidden",   settings.no_special },
    { "unlock all levels",       menu.unlocked_all },
  }
  for i, row in ipairs(rows) do
    local y = 30 + (i - 1) * 14
    love.graphics.setColor(pcol(i == menu.menu_sel and 12 or 7))
    love.graphics.print((i == menu.menu_sel and ">" or " ") .. row[1], 26, y)
    love.graphics.setColor(pcol(row[2] and 10 or 8))
    love.graphics.print(row[2] and "on" or "off", 276, y)
  end
  love.graphics.setColor(pcol(menu.menu_sel == 6 and 12 or 7))
  love.graphics.print("> level select", 26, 100)

  love.graphics.setColor(pcol(12))
  love.graphics.print("up/down: select  c: toggle  z/x: close", 26, 132)
  love.graphics.print("m / start: panel", 26, 146)
  love.graphics.setColor(1, 1, 1, 1)
end
