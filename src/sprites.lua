-- Tile and sprite art: image loading and quad construction.
--
-- Art comes from per-level tilesets, so there is no single global
-- spritesheet any more. Each tile record built by src/tiled.lua names
-- the image it lives in, its source rect within it, and its cell size
-- (8x8 for terrain, 16x16 for characters); this module turns that into
-- a drawable quad, caching both the loaded images and the quads so a
-- tile drawn a thousand times a frame costs one lookup.
--
-- Two levels may use different images freely: the image cache is keyed
-- by path, and quads are cached per tile record, so swapping tilesets
-- between levels changes nothing else.

local Sprites = {}

-- image path -> love Image. Quads are cached on the tile records
-- themselves (see Sprites.quad), since a record already knows its rect.
local images = {}

-- Loads (or returns the already-loaded) image for a path. Missing art
-- must not take the game down: a level can reference a tileset whose
-- image is not in the build, and the error belongs in the log, not on
-- the player's screen.
function Sprites.image(path)
  local img = images[path]
  if img == nil then
    local ok, res = pcall(love.graphics.newImage, path)
    if ok then
      img = res
    else
      print("sprites: warning - cannot load image '" .. tostring(path)
        .. "' (" .. tostring(res) .. "); its tiles will not draw")
      img = false
    end
    images[path] = img
  end
  return img or nil
end

-- The drawable quad for a tile record (see src/tiled.lua): its source
-- rect in its own image, cached on the record's geometry so two tiles
-- sharing a rect share a quad.
function Sprites.quad(rec)
  if rec == nil then return nil end
  if rec.quad == nil then
    local img = Sprites.image(rec.image)
    if img == nil then return nil end
    rec.quad = love.graphics.newQuad(rec.sx, rec.sy, rec.w, rec.h,
      img:getWidth(), img:getHeight())
  end
  return rec.quad
end

-- Draws the tile record `rec` at world position x/y. `flip` mirrors it
-- horizontally, `rot` is a multiple of 90 degrees (from the Tiled
-- object). Positions are floored: bodies move at fractional speeds,
-- and drawing at fractional coords rasterizes unevenly on the pixel
-- canvas (a sprite's edges wobble between 8 and 9 px), which reads as
-- jitter. `tint` is an optional {r, g, b, a} overlay: the sprite is
-- drawn a second time in the tint colour (the texture's own alpha masks
-- it to the sprite's pixels), so e.g. the i-frame shield reads as a red
-- silhouette that never hides the art.
function Sprites.draw(rec, x, y, flip, rot, tint)
  local q = Sprites.quad(rec)
  if q == nil then return end
  local img = images[rec.image]
  local w, h = rec.w, rec.h
  x, y = math.floor(x), math.floor(y)
  love.graphics.setColor(1, 1, 1, 1)
  local function blit(dx, dy, sx, sy)
    dx, dy, sx, sy = dx or 0, dy or 0, sx or 1, sy or 1
    if rot then
      -- rotated: pivot the sprite's corner so it still fills its cell
      local rad = math.rad(rot)
      local ox, oy = 0, 0
      if rot == 90 then ox, oy = w, 0
      elseif rot == 180 then ox, oy = w, h
      elseif rot == 270 then ox, oy = 0, h end
      love.graphics.draw(img, q, x + dx + ox, y + dy + oy, rad)
    elseif flip then
      love.graphics.draw(img, q, x + dx + w, y + dy, 0, -sx, sy)
    else
      love.graphics.draw(img, q, x + dx, y + dy)
    end
  end
  blit()
  if tint then
    love.graphics.setColor(tint[1], tint[2], tint[3], tint[4])
    blit()
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- Drops the quad cached on a tile record, so a reloaded tileset picks
-- up new art without a process restart.
function Sprites.forget(rec)
  if rec then rec.quad = nil end
end

-- Test seam: forget every cached image and quad.
function Sprites.reset()
  images = {}
end

return Sprites
