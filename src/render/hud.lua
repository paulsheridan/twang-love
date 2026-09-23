-- HUD: power indicator and control hints, drawn at window scale.
--
-- Anchored to the blitted canvas rect so text stays readable and aligned
-- even when the window is resized (see src/render/blit.lua for the metrics).

local config = require("src.config")
local Palette = require("src.palette")

local pcol = Palette.rgb

-- Power indicator colours and labels (lo/md/hi), matching the cart.
local POWER_COLOURS = { [1]=12, [2]=10, [3]=8 }
local POWER_LABELS = { "lo", "md", "hi" }

-- Seconds -> "m:ss" (the level clock; the results panel shows tenths).
local function fmt_time(t)
  return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

return function(ctx, blit)
  local vw, vh = config.view.width, config.view.height
  love.graphics.push()
  love.graphics.translate(blit.ox, blit.oy)
  love.graphics.scale(blit.scale)
  if not config.enemies.enabled then
    love.graphics.setColor(pcol(8))
    love.graphics.print("enemies off", 2, 14)
    love.graphics.setColor(1, 1, 1, 1)
  end
  local menu = ctx.menu
  -- level clock, top-centre while playing (heart slots top-left, arrow
  -- type top-right)
  if menu and menu.mode == "play" and not menu.menu_open then
    love.graphics.setColor(pcol(7))
    love.graphics.print(fmt_time(menu.play_steps / config.sim.rate),
      vw / 2 - 16, 2)
    love.graphics.setColor(1, 1, 1, 1)
  end
  -- equipped arrow type: always shown top-right (rope colour when rope)
  local p = ctx.player
  if p.arrow_kind == "rope" then
    love.graphics.setColor(pcol(config.rope.colour))
  else
    love.graphics.setColor(pcol(7))
  end
  love.graphics.print(p.arrow_kind, vw - 40, 2)
  if ctx.input:down("aim") then
    love.graphics.setColor(pcol(POWER_COLOURS[p.aim_power]))
    love.graphics.print("pwr:" .. POWER_LABELS[p.aim_power], vw - 40, 10)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("z:aim  lr:ang  ud:pwr", 2, vh - 12)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("x:jump  z:bow  c:arrow", 2, vh - 12)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end
