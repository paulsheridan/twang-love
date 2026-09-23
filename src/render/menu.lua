-- Test menu panel, drawn on the 480x320 canvas (pixelated). Four test
-- toggles (see Game:menu_step): puzzle pieces hidden, invincibility and
-- enemies on/off, unlock-all levels (progress gating off), plus a row
-- that returns to the launch level select. Selection state lives on the
-- Game (ctx.menu).

local config = require("src.config")
local Palette = require("src.palette")

local pcol = Palette.rgb

return function(ctx)
  local menu = ctx.menu
  local settings = menu.settings

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 30, 34, 200, 132)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", 30.5, 34.5, 199, 131)

  love.graphics.setColor(pcol(10))
  love.graphics.print("test menu", 96, 40)

  local rows = {
    { "doors/keys/locks hidden", settings.no_puzzle },
    { "invincibility",           settings.invincible },
    { "enemies enabled",         config.enemies.enabled },
    { "unlock all levels",       menu.unlocked_all },
  }
  for i, row in ipairs(rows) do
    local y = 56 + (i - 1) * 12
    love.graphics.setColor(pcol(i == menu.menu_sel and 12 or 7))
    love.graphics.print((i == menu.menu_sel and ">" or " ") .. row[1], 44, y)
    love.graphics.setColor(pcol(row[2] and 10 or 8))
    love.graphics.print(row[2] and "on" or "off", 196, y)
  end
  love.graphics.setColor(pcol(menu.menu_sel == 5 and 12 or 7))
  love.graphics.print("> level select", 44, 104)

  love.graphics.setColor(pcol(12))
  love.graphics.print("up/down: select  c: toggle  z/x: close", 44, 118)
  love.graphics.print("m / start: panel", 44, 128)
  love.graphics.setColor(1, 1, 1, 1)
end
