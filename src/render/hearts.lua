-- Heart HUD: the player's remaining health, drawn on the 480x320 canvas
-- top-left from the spritesheet. Health is tracked in half-hearts, so a
-- heart slot is full (red, Tiled tile 12,7), half-drained (13,7) or empty
-- (fully gray, 14,7); each hit drains half a heart.

local config = require("src.config")
local Sprites = require("src.sprites")

local FULL_SPRITE  = 107  -- sheet cell (11,6) = Tiled tile (12,7)
local HALF_SPRITE  = 108  -- sheet cell (12,6) = Tiled tile (13,7)
local EMPTY_SPRITE = 109  -- sheet cell (13,6) = Tiled tile (14,7)

local SPACING = 18
local OX, OY = 6, 6

return function(ctx)
  local p = ctx.player
  local hp = p.hp or config.player.hearts * 2
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, config.player.hearts do
    local left = hp - (i - 1) * 2
    local sprite = EMPTY_SPRITE
    if left >= 2 then
      sprite = FULL_SPRITE
    elseif left == 1 then
      sprite = HALF_SPRITE
    end
    Sprites.draw(sprite, OX + (i - 1) * SPACING, OY)
  end
end
