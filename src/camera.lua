-- Camera: smooth follow with pixel clamping to the active room's bounds
-- (the whole map on roomless maps -- see World:clamp_rect), plus a
-- decaying random shake for explosions.

local config = require("src.config")

local Camera = {}

function Camera.new()
  return { x = 0, y = 0 }
end

-- Clamps a target position so the view stays inside the active room.
function Camera.clamp(x, y, world)
  local lo_x, hi_x, lo_y, hi_y = world:clamp_rect()
  return math.max(lo_x, math.min(hi_x, x)),
         math.max(lo_y, math.min(hi_y, y))
end

-- Snaps the camera straight onto a position (used at spawn; pico-8
-- snapped per screen, no slow pan).
function Camera.snap(cam, player, world)
  local lo_x, hi_x, lo_y, hi_y = world:clamp_rect()
  local vw, vh = config.view.width, config.view.height
  cam.x = math.max(lo_x, math.min(hi_x, player.x + player.w/2 - vw/2))
  cam.y = math.max(lo_y, math.min(hi_y, player.y + player.h/2 - vh/2))
  cam.shake_t, cam.shake_s = nil, nil  -- a snap clears any shake
end

-- Kicks off a decaying shake for a detonation: `radius` is the blast's
-- radius (px) -- the bigger the boom, the harder the frame shakes. The
-- jitter rides the clamped follow (see update) and decays over
-- `camera.shake_steps`, ending on its own.
function Camera.shake(cam, radius)
  cam.shake_t = config.camera.shake_steps
  cam.shake_s = math.max(3, math.min(9, radius * 0.15))
end

-- Smooth follow: eases toward the player each step, clamped to the
-- world. The follow fraction is applied over `dt` steps of world time
-- (exponent-scaled, so slow motion slows the pan with the world).
function Camera.update(cam, player, world, dt)
  local vw, vh = config.view.width, config.view.height
  local tx = player.x + player.w/2 - vw/2
  local ty = player.y + player.h/2 - vh/2
  tx, ty = Camera.clamp(tx, ty, world)
  local f = 1 - (1 - config.camera.follow) ^ dt
  cam.x = cam.x + (tx - cam.x) * f
  cam.y = cam.y + (ty - cam.y) * f
  -- explosion shake: random jitter re-rolled every step on top of the
  -- clamped follow position, decaying linearly to nothing (the follow
  -- absorbs the offset, so the shake self-corrects as it decays)
  if cam.shake_t and cam.shake_t > 0 then
    local k = math.min(1, cam.shake_t / (config.camera.shake_steps or 8))
    local s = (cam.shake_s or 0) * k
    cam.x = cam.x + (math.random() * 2 - 1) * s
    cam.y = cam.y + (math.random() * 2 - 1) * s
    cam.shake_t = cam.shake_t - dt
    if cam.shake_t <= 0 then
      cam.shake_t, cam.shake_s = nil, nil
    end
  end
end

return Camera
