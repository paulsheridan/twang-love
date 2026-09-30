-- Heart HUD: the player's remaining health, drawn on the 480x320 canvas
-- top-left. The three heart states are named roles in the level's art
-- ("heart_full" / "heart_half" / "heart_empty"), so the HUD restyles
-- with the tilesets. Health is tracked in half-hearts; each hit drains
-- half a heart.

local config = require("src.config")
local Sprites = require("src.sprites")

local SPACING = 18
local OX, OY = 6, 6

return function(ctx)
  local p = ctx.player
  local A = ctx.art or {}
  local hp = p.hp or config.player.hearts * 2
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, config.player.hearts do
    local left = hp - (i - 1) * 2
    local art = A.heart_empty
    if left >= 2 then
      art = A.heart_full
    elseif left == 1 then
      art = A.heart_half
    end
    Sprites.draw(art, OX + (i - 1) * SPACING, OY)
  end
end
