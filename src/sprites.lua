-- Spritesheet access: quad caching and the sprite draw helper.
--
-- The sheet is the pico-8 spritesheet layout: 16 columns of 8x8 sprites,
-- indexed 0..255. Rotated sprites pivot about the corner that keeps them
-- filling their cell (90 -> top-right, 180 -> bottom-right, 270 -> bottom-left).

local config = require("src.config")

local Sprites = {}

local sheet = nil
local quads = {}

function Sprites.init(image)
  sheet = image
  quads = {}
end

-- The loaded spritesheet image (needed by code that draws tiles directly).
function Sprites.sheet()
  return sheet
end

function Sprites.quad(s)
  if not quads[s] then
    local tw = config.tile_size
    quads[s] = love.graphics.newQuad(
      (s % 16) * tw, math.floor(s / 16) * tw, tw, tw,
      sheet:getWidth(), sheet:getHeight())
  end
  return quads[s]
end

-- Draws sprite s at world position x/y; `flip` mirrors horizontally,
-- `rot` is a multiple of 90 (degrees, from the Tiled object).
-- Positions are floored: bodies move at fractional speeds, and drawing
-- at fractional coords rasterizes unevenly on the pixel canvas (the
-- sprite's edges wobble between 8 and 9 px), which reads as jitter.
function Sprites.draw(s, x, y, flip, rot)
  local q = Sprites.quad(s)
  local tw = config.tile_size
  x, y = math.floor(x), math.floor(y)
  love.graphics.setColor(1, 1, 1, 1)
  if rot then
    -- rotated: pivot the sprite's corner so it still fills its cell
    local rad = math.rad(rot)
    local ox, oy = 0, 0
    if rot == 90 then ox, oy = tw, 0
    elseif rot == 180 then ox, oy = tw, tw
    elseif rot == 270 then ox, oy = 0, tw end
    love.graphics.draw(sheet, q, x + ox, y + oy, rad)
  elseif flip then
    love.graphics.draw(sheet, q, x + tw, y, 0, -1, 1)
  else
    love.graphics.draw(sheet, q, x, y)
  end
end

return Sprites
