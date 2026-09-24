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
local render_levelselect = require("src.render.levelselect")
local render_results = require("src.render.results")

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

-- One rendered frame: world + (level select / results / menu overlay)
-- into the native canvas, blit to the window, then HUD.
function Blit.render(ctx, menu_open, level_select, complete)
  local vw, vh = config.view.width, config.view.height
  love.graphics.setCanvas(canvas)
  -- background: sky blue (levels carry no backdrop sprites; pits and
  -- open air read as sky)
  love.graphics.clear(config.world.sky[1], config.world.sky[2],
    config.world.sky[3], 1)
  -- world-pass vector lines (arrow shafts, rope, aim lines) draw 2px thick
  -- to match the 2x2-upscaled sheet; the controls panel resets its own 1px
  love.graphics.setLineWidth(2)
  love.graphics.push()
  love.graphics.translate(-math.floor(ctx.cam.x), -math.floor(ctx.cam.y))
  render_world.world(ctx)
  render_player(ctx)
  render_world.foreground(ctx)  -- buildings/hidden spaces, above the player
  love.graphics.pop()
  -- HUD on the canvas: hearts live in screen space (outside the camera
  -- translate), so they stay pinned to the top-left corner
  render_hearts(ctx)
  -- room-transition wipe: black at the fade's progress (the test menu
  -- renders above it; hearts live below)
  local f = ctx.menu and ctx.menu.room_fade
  if f then
    local steps = config.rooms.fade_steps
    local a = (f.phase == "out") and math.min(f.t / steps, 1)
                                   or math.max(0, 1 - f.t / steps)
    love.graphics.setColor(0, 0, 0, a)
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if level_select then render_levelselect(ctx)
  elseif complete then render_results(ctx)
  elseif menu_open then render_menu(ctx) end
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
