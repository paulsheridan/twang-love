-- Canvas blit: renders the world into the 480x320 native canvas, then
-- blits it to the window preserving aspect ratio, remembering the blit
-- rect so HUD text can anchor to it (see src/render/hud.lua).

local config = require("src.config")
local Palette = require("src.palette")

local render_world  = require("src.render.world")
local render_player = require("src.render.player")
local render_hearts = require("src.render.hearts")
local render_hud    = require("src.render.hud")
local render_menu   = require("src.render.menu")

local Blit = {}

local canvas = nil
-- Last blit metrics (window-space scale + offset); the HUD anchors to it.
local blit = {scale = 1, ox = 0, oy = 0}

function Blit.init()
  canvas = love.graphics.newCanvas(config.view.width, config.view.height)
  canvas:setFilter("nearest", "nearest")
end

function Blit.canvas()
  return canvas
end

-- One rendered frame: world + (menu overlay) into the native canvas,
-- blit to the window, then HUD.
function Blit.render(ctx, menu_open)
  local vw, vh = config.view.width, config.view.height
  love.graphics.setCanvas(canvas)
  love.graphics.clear(Palette.rgb(1))
  -- world-pass vector lines (arrow shafts, rope, aim lines) draw 2px thick
  -- to match the 2x2-upscaled sheet; the controls panel resets its own 1px
  love.graphics.setLineWidth(2)
  love.graphics.push()
  love.graphics.translate(-math.floor(ctx.cam.x), -math.floor(ctx.cam.y))
  render_world.world(ctx)
  render_player(ctx)
  love.graphics.pop()
  -- HUD on the canvas: hearts live in screen space (outside the camera
  -- translate), so they stay pinned to the top-left corner
  render_hearts(ctx)
  if menu_open then render_menu() end
  love.graphics.setCanvas()

  -- blit the native canvas to the window at an INTEGER scale: fractional
  -- scales give some pixels more screen space than others, breaking the
  -- crisp GBA look. Centre the result and letterbox the remainder
  -- (fullscreen included: the world always scales by a whole number),
  -- with a clean black background behind the bars
  love.graphics.setCanvas()
  love.graphics.clear()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setScissor()
  local sw, sh = love.graphics.getDimensions()
  local scale = math.max(1, math.floor(math.min(sw / vw, sh / vh)))
  local ox    = math.floor((sw - vw * scale) / 2)
  local oy    = math.floor((sh - vh * scale) / 2)
  love.graphics.draw(canvas, ox, oy, 0, scale)
  blit.scale, blit.ox, blit.oy = scale, ox, oy

  render_hud(ctx, blit)
end

return Blit
