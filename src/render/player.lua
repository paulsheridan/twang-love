-- Player rendering: sprite state machine, carried key, and the aim
-- indicator with its bounce-aware trajectory preview.

local config = require("src.config")
local Palette = require("src.palette")
local Util = require("src.util")
local Sprites = require("src.sprites")
local Player = require("src.player")

local pcol = Palette.rgb

return function(ctx)
  local p = ctx.player

  -- i-frames: blink the player (and its aim preview) while shielded
  if p.invuln and p.invuln > 0 and (p.invuln % 6) < 3 then
    return
  end

  local s
  if not p.gr then
    s = 97
  elseif p.vx ~= 0 and not ctx.input:down("aim") then
    s = 100 + (Player.run_state())
  else
    s = 96
  end
  local threshold = config.aiming.downward_sin_threshold
  if p.land_frames > 0 then s = 99
  elseif ctx.input:down("aim") and Util.p8sin(p.aim_angle) > threshold then s = 98
  elseif p.aimed_down and not p.gr then s = 98
  end

  local draw_facing = p.facing
  if ctx.input:down("aim") then
    local ax = Util.p8cos(p.aim_angle)
    if ax > 0 then draw_facing = 1
    elseif ax < 0 then draw_facing = -1 end
  end
  Sprites.draw(s, p.x - 2, p.y - 2, draw_facing < 0)
  -- a carried key rides centred on the player
  if p.key then
    Sprites.draw(ctx.tiles.key, p.x - 2, p.y - 1)
  end

  -- aim indicator + predicted trajectory (floored: fractional line/point
  -- coords shimmer on the pixel canvas)
  if ctx.input:down("aim") then
    local tw = config.tile_size
    local vw, vh = config.view.width, config.view.height
    local cfg = config.arrows
    local cx, cy = math.floor(p.x + p.w/2), math.floor(p.y + p.h/2)
    local spd = cfg.speeds[p.aim_power]
    if Util.p8sin(p.aim_angle) <= threshold then
      local ex = cx + math.floor(Util.p8cos(p.aim_angle) * tw)
      local ey = cy + math.floor(Util.p8sin(p.aim_angle) * tw)
      love.graphics.setColor(pcol(10))
      love.graphics.line(cx, cy, ex, ey)
    end
    local tvx  = Util.p8cos(p.aim_angle) * spd
    local tvy  = Util.p8sin(p.aim_angle) * spd
    local tx, ty = cx, cy
    love.graphics.setColor(pcol(cfg.colour))
    -- bounce-aware preview: reflects off sticky surfaces exactly like a
    -- flying arrow, and stops where the arrow would stick. dots every
    -- step, preview_steps total: a shorter, tighter line now that arrows
    -- fly faster
    local world = ctx.world
    for _ = 1, cfg.preview_steps do
      tvy = tvy + cfg.gravity
      local nx, ny = tx + tvx, ty + tvy
      if world:solid_for_arrow(nx, ny) then
        local hx = world:solid_for_arrow(nx, ty)
        local hy = world:solid_for_arrow(tx, ny)
        local sticky = (hx and world:sticky_at(nx, ty))
                    or (hy and world:sticky_at(tx, ny))
                    or (not hx and not hy and world:sticky_at(nx, ny))
        if sticky then
          if hx then tvx = -tvx end
          if hy then tvy = -tvy end
          if not hx and not hy then tvx, tvy = -tvx, -tvy end
        else
          love.graphics.points(math.floor(nx), math.floor(ny))  -- sticks here
          break
        end
      end
      tx, ty = nx, ny
      love.graphics.points(math.floor(tx), math.floor(ty))
    end
  end
end
