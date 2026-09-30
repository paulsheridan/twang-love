-- Player rendering: sprite state machine, carried key, the per-kind
-- body tints (i-frame shield red; spirit equipped = ghostly blue) and
-- the aim indicator (bounce-aware arc for arrows, fling trail for the
-- spirit).

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

return function(ctx, alpha)
  local p = ctx.player
  -- the body eases between the last two sim states like everything
  -- else (the aim preview reads live state: the bow is real-time)
  local px, py = Util.render_pos(p, alpha or 1)

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
  elseif p.arrow_kind == "spirit" then
    -- the spirit arrow: while its kind is equipped the body reads as
    -- ghostly blue (same silhouette-masking overlay as the shield; the
    -- i-frame red above wins while it lasts so hits stay legible)
    local scfg = config.spirit
    local r, g, b = pcol(scfg.tint_colour)
    tint = { r, g, b, scfg.tint_alpha }
  end

  -- Frames are named roles in the level's art (config.art merged with
  -- the level's tilesets): "player_run_0..n" is a cycle and
  -- "player_run" is its fallback, so a level can restyle the player by
  -- declaring the same kinds in its own character tileset.
  local A = ctx.art or {}
  local function frame(base, i)
    return A[base .. "_" .. tostring(i)] or A[base]
  end
  local s
  if p.wallrun then
    s = frame(config.wallrun.art, Player.wallrun_state())
  elseif not p.gr then
    s = A.player_air
  elseif p.vx ~= 0 and not ctx.input:down("aim") then
    s = frame(config.player.art_run, Player.run_state())
  else
    s = A.player_idle
  end
  local threshold = config.aiming.downward_sin_threshold
  if p.land_frames > 0 then s = A.player_land
  elseif not p.gr and ctx.input:down("aim")
  and Util.p8sin(p.aim_angle) > threshold then s = A.player_aim_down
  elseif p.aimed_down and not p.gr then s = A.player_aim_down
  end

  local draw_facing = p.facing
  if ctx.input:down("aim") then
    local ax = Util.p8cos(p.aim_angle)
    if ax > 0 then draw_facing = 1
    elseif ax < 0 then draw_facing = -1 end
  end
  Sprites.draw(s, px - 4, py - 4, draw_facing < 0, nil, tint)
  -- a carried key rides centred on the player
  if p.key then
    Sprites.draw(ctx.art and ctx.art.key, px - 4, py - 2)
  end
  -- a held gun reads at the hip: a chunky dark slab (the placeholder
  -- art; the pickup and the fired shell share it) until real art lands
  if p.guns and p.guns > 0 then
    love.graphics.setColor(pcol(1))
    love.graphics.rectangle("fill", math.floor(px) + 3, math.floor(py) - 1, 5, 3)
    love.graphics.setColor(pcol(8))
    love.graphics.rectangle("fill", math.floor(px) + 7, math.floor(py) - 1, 1, 3)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- aim indicator + predicted trajectory (floored: fractional line/point
  -- coords shimmer on the pixel canvas)
  if ctx.input:down("aim") then
    local tw = config.art_size
    local vw, vh = config.view.width, config.view.height
    local cfg = config.arrows
    local scfg = config.spirit
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
    if p.arrow_kind == "spirit" then
      -- spirit preview: no projectile exists, so the dots show the
      -- FLING instead -- a short spirit-coloured trail from the bow
      -- opening along the exact opposite of the aim (the way the body
      -- is about to fly): read it as "you go out along this line,
      -- away from where you point"
      local fx, fy = -Util.p8cos(p.aim_angle), -Util.p8sin(p.aim_angle)
      love.graphics.setColor(pcol(scfg.tint_colour))
      for i = 1, 5 do
        local t = i * 6
        dot(cx + fx * t, cy + fy * t)
      end
    else
      local tvx  = Util.p8cos(p.aim_angle) * spd
      local tvy  = Util.p8sin(p.aim_angle) * spd
      local tx, ty = cx, cy
      -- bounce-aware preview: reflects off bounce surfaces exactly like a
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
          local bouncy = (hx and world:sticky_at(nx, ty))
                      or (hy and world:sticky_at(tx, ny))
                      or (not hx and not hy and world:sticky_at(nx, ny))
          if bouncy then
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
