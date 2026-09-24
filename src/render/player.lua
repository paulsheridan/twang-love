-- Player rendering: sprite state machine, carried key, and the aim
-- indicator with its bounce-aware trajectory preview.

local config = require("src.config")
local Palette = require("src.palette")
local Util = require("src.util")
local Sprites = require("src.sprites")
local Player = require("src.player")

local pcol = Palette.rgb

-- Aim/preview dots draw as 2x2 pixel blocks (2x of their size on the old
-- 240x160 canvas); lines are 2px, set in render/blit.lua for the world pass.
local function dot(x, y)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), 2, 2)
end

return function(ctx)
  local p = ctx.player

  -- i-frames: a red silhouette overlay that fades out as the shield
  -- lapses (replaces the old blink, which hid the player during slow
  -- motion). Fully opaque when the hit is fresh, easing to nothing.
  local tint = nil
  if p.invuln and p.invuln > 0 then
    local cfg = config.player
    local fade = math.min(p.invuln, cfg.shield_tint_fade_steps)
                   / cfg.shield_tint_fade_steps
    local r, g, b = pcol(cfg.shield_tint_colour)
    tint = { r, g, b, cfg.shield_tint_alpha * fade }
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
  Sprites.draw(s, p.x - 4, p.y - 4, draw_facing < 0, nil, tint)
  -- a carried key rides centred on the player
  if p.key then
    Sprites.draw(ctx.tiles.key, p.x - 4, p.y - 2)
  end

  -- aim indicator + predicted trajectory (floored: fractional line/point
  -- coords shimmer on the pixel canvas)
  if ctx.input:down("aim") then
    local tw = config.tile_size
    local vw, vh = config.view.width, config.view.height
    local cfg = config.arrows
    local scfg = config.shockwave
    local cx, cy = math.floor(p.x + p.w/2), math.floor(p.y + p.h/2)
    -- the preview launches at the same speed as the real shot: the
    -- analog stick force scales it just like Arrows.fire does
    local spd = cfg.speeds[p.aim_power] * (p.aim_force or 1)
    if Util.p8sin(p.aim_angle) <= threshold then
      local ex = cx + math.floor(Util.p8cos(p.aim_angle) * tw)
      local ey = cy + math.floor(Util.p8sin(p.aim_angle) * tw)
      love.graphics.setColor(pcol(10))
      love.graphics.line(cx, cy, ex, ey)
    end
    local world = ctx.world
    love.graphics.setColor(pcol(cfg.colour))
    if p.arrow_kind == "shockwave" then
      -- wave preview: straight flight that bounces off anything (the
      -- wave never sticks), dots every preview_dot_px of flight,
      -- stopping at the fizzle range; the front's full-grown arc
      -- (opening along the final heading) shows the swept size
      local w_spd = scfg.speeds[p.aim_power]
        * math.max(p.aim_force or 1, scfg.min_force_scale)
      local tvx = Util.p8cos(p.aim_angle) * w_spd
      local tvy = Util.p8sin(p.aim_angle) * w_spd
      local tx, ty = cx, cy
      local traveled, next_dot, guard = 0, 0, 0
      while traveled < scfg.max_range and guard < 96 do
        guard = guard + 1
        local nx, ny = tx + tvx, ty + tvy
        if world:solid_for_arrow(nx, ny) or world:in_slope_solid(nx, ny) then
          local hx = world:solid_for_arrow(nx, ty) or world:in_slope_solid(nx, ty)
          local hy = world:solid_for_arrow(tx, ny) or world:in_slope_solid(tx, ny)
          if hx then tvx = -tvx end
          if hy then tvy = -tvy end
          if not hx and not hy then tvx, tvy = -tvx, -tvy end
        end
        local step_len = math.sqrt((nx-tx)^2 + (ny-ty)^2)
        tx, ty = nx, ny
        traveled = traveled + step_len
        if traveled >= next_dot then
          dot(tx, ty)
          next_dot = next_dot + scfg.preview_dot_px
        end
      end
      love.graphics.setColor(pcol(scfg.colour))
      local wlen = math.sqrt(tvx*tvx + tvy*tvy)
      if wlen > 0 then
        local fx, fy = tvx/wlen, tvy/wlen
        local qx, qy = -fy, fx
        local arc_steps = math.max(6, math.floor(scfg.radius_max))
        for i = 0, arc_steps do
          local t = (i / arc_steps) * 2 - 1
          local s = math.sqrt(1 - t*t)
          dot(tx + (fx * s + qx * t) * scfg.radius_max,
              ty + (fy * s + qy * t) * scfg.radius_max)
        end
      end
    else
      local tvx  = Util.p8cos(p.aim_angle) * spd
      local tvy  = Util.p8sin(p.aim_angle) * spd
      local tx, ty = cx, cy
      -- bounce-aware preview: reflects off sticky surfaces exactly like a
      -- flying arrow, and stops where the arrow would stick. dots every
      -- step, preview_steps total: a shorter, tighter line now that arrows
      -- fly faster. A bomb arrow detonates at that contact instead of
      -- sticking: its trail stops one dot short and the blast's catch
      -- radius is ringed there, so the player can read their own fling
      local bomb = p.arrow_kind == "bomb"
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
            if not bomb then dot(nx, ny) end  -- sticks here
            break
          end
        end
        tx, ty = nx, ny
        dot(tx, ty)
      end
      if bomb then
        love.graphics.setColor(pcol(9))
        love.graphics.circle("line", math.floor(tx), math.floor(ty),
          config.bomb_arrow.blast_radius)
      end
    end
  end
end
