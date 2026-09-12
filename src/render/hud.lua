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

return function(ctx, blit)
  local vw, vh = config.view.width, config.view.height
  love.graphics.push()
  love.graphics.translate(blit.ox, blit.oy)
  love.graphics.scale(blit.scale)
  if ctx.input:down("aim") then
    local p = ctx.player
    love.graphics.setColor(pcol(POWER_COLOURS[p.aim_power]))
    love.graphics.print("pwr:" .. POWER_LABELS[p.aim_power], vw - 40, 2)
    if p.arrow_kind == "rope" then
      love.graphics.setColor(pcol(config.rope.colour))
      love.graphics.print("rope", vw - 40, 10)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("z:aim  lr:ang  ud:pwr", 2, vh - 12)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("x:jump  z:bow", 2, vh - 12)
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end
