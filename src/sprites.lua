-- Spritesheet access: quad caching and the sprite draw helper.
--
-- The sheet is the pico-8 spritesheet layout: 16 columns of 16x16 art
-- cells (2x2 upscales of the original 8x8 art), indexed 0..255. Terrain
-- rendering draws 8x8 sub-tiles instead: the 8px tileset re-indexes the
-- same image as 32 columns of 8px cells (old art cell O = the four
-- sub-tiles at (O//16)*64 + (O%16)*2 + {0,1,32,33}; see
-- Sprites.tile_quad). Rotated sprites pivot about the
-- corner that keeps them filling their cell (90 -> top-right,
-- 180 -> bottom-right, 270 -> bottom-left).

local config = require("src.config")

local Sprites = {}

local sheet = nil
local quads = {}
local tile_quads = {}

function Sprites.init(image)
  sheet = image
  quads = {}
  tile_quads = {}
end

-- The loaded spritesheet image (needed by code that draws tiles directly).
function Sprites.sheet()
  return sheet
end

-- The quad for a 16px art cell (entity/sprite label id 0..255).
function Sprites.quad(s)
  if not quads[s] then
    quads[s] = love.graphics.newQuad(
      (s % 16) * 16, math.floor(s / 16) * 16, 16, 16,
      sheet:getWidth(), sheet:getHeight())
  end
  return quads[s]
end

-- The quad for an 8px terrain sub-tile (0..1023): the tileset's 32
-- columns of 8px cells over the same image.
function Sprites.tile_quad(t)
  if not tile_quads[t] then
    local tw = config.tile_size
    tile_quads[t] = love.graphics.newQuad(
      (t % 32) * tw, math.floor(t / 32) * tw, tw, tw,
      sheet:getWidth(), sheet:getHeight())
  end
  return tile_quads[t]
end

-- Draws the 16px sprite s at world position x/y; `flip` mirrors
-- horizontally, `rot` is a multiple of 90 (degrees, from the Tiled
-- object). Positions are floored: bodies move at fractional speeds, and
-- drawing at fractional coords rasterizes unevenly on the pixel canvas
-- (the sprite's edges wobble between 8 and 9 px), which reads as jitter.
-- `tint` is an optional {r, g, b, a} overlay: the sprite is drawn a
-- second time in the tint colour (the texture's own alpha masks it to
-- the sprite's pixels), so e.g. the i-frame shield reads as a red
-- silhouette that never hides the art.
function Sprites.draw(s, x, y, flip, rot, tint)
  local q = Sprites.quad(s)
  local tw = 16
  x, y = math.floor(x), math.floor(y)
  love.graphics.setColor(1, 1, 1, 1)
  local function blit(dx, dy, sx, sy)
    dx, dy, sx, sy = dx or 0, dy or 0, sx or 1, sy or 1
    if rot then
      -- rotated: pivot the sprite's corner so it still fills its cell
      local rad = math.rad(rot)
      local ox, oy = 0, 0
      if rot == 90 then ox, oy = tw, 0
      elseif rot == 180 then ox, oy = tw, tw
      elseif rot == 270 then ox, oy = 0, tw end
      love.graphics.draw(sheet, q, x + dx + ox, y + dy + oy, rad)
    elseif flip then
      love.graphics.draw(sheet, q, x + dx + tw, y + dy, 0, -sx, sy)
    else
      love.graphics.draw(sheet, q, x + dx, y + dy)
    end
  end
  blit()
  if tint then
    love.graphics.setColor(tint[1], tint[2], tint[3], tint[4])
    blit()
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Sprites
