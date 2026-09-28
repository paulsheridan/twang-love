-- Camera: smooth follow with pixel clamping to the active room's bounds
-- (the whole map on roomless maps -- see World:clamp_rect), plus a
-- decaying random shake for explosions.

local config = require("src.config")

local Camera = {}

function Camera.new()
  return { x = 0, y = 0, ptx = nil, pty = nil }
end

-- Clamps a target position so the view stays inside the active room.
function Camera.clamp(x, y, world)
  local lo_x, hi_x, lo_y, hi_y = world:clamp_rect()
  return math.max(lo_x, math.min(hi_x, x)),
         math.max(lo_y, math.min(hi_y, y))
end

-- Snaps the camera straight onto a position (used at spawn; pico-8
-- snapped per screen, no slow pan). The feed-forward's previous-target
-- memory resets with it, so the next step's delta is not stale. The
-- render-interpolation shadows reset too (no cross-map ease).
function Camera.snap(cam, player, world)
  local lo_x, hi_x, lo_y, hi_y = world:clamp_rect()
  local vw, vh = config.view.width, config.view.height
  cam.x = math.max(lo_x, math.min(hi_x, player.x + player.w/2 - vw/2))
  cam.y = math.max(lo_y, math.min(hi_y, player.y + player.h/2 - vh/2))
  cam.px, cam.py = cam.x, cam.y
  cam.ptx, cam.pty = cam.x, cam.y
  cam.shake_t, cam.shake_s, cam.shake_len = nil, nil, nil  -- a snap clears any shake
end

-- Kicks off a decaying shake for a detonation: `radius` is the blast's
-- radius (px) -- the bigger the boom, the harder the frame shakes. The
-- jitter rides the clamped follow (see update) and decays over
-- `camera.shake_steps`, ending on its own.
function Camera.shake(cam, radius)
  cam.shake_t = config.camera.shake_steps
  cam.shake_len = config.camera.shake_steps
  cam.shake_s = math.max(3, math.min(9, radius * 0.15))
end

-- A small "thud" shake: jump/land/fire feedback. Same decay mechanics
-- as the blast shake (random jitter re-rolled per step on top of the
-- clamped follow), but a shorter decay and a much smaller offset.
-- Calling while a blast shake is live keeps the blast (the stronger
-- read wins; thuds never override one).
function Camera.thud(cam, strength)
  if strength <= 0 then return end
  if cam.shake_t and cam.shake_t > 0 then return end
  cam.shake_t = config.camera.thud_steps
  cam.shake_len = config.camera.thud_steps
  cam.shake_s = strength
end

-- Smooth follow: eases toward the player each step, clamped to the
-- world. The follow fraction is applied over `dt` steps of world time
-- (exponent-scaled, so slow motion slows the pan with the world).
--
-- While the player RIDES a moving block (p.ride, src/movers.lua) the
-- camera takes a FEED-FORWARD share of the target's own motion: the
-- carried rider moves at a steady rate the pure ease would take a
-- dozen-odd steps to match (the ride's start would read as the player
-- stuttering to life on screen), and an eased-only chase converges
-- asymptotically, whose fractional crawl blinks against the block's
-- exact whole-pixel steps. The feed-forward carries the ride's
-- velocity exactly: the camera inherits (1 - f) of it at once, the
-- eased share only trims the residual lag, and the steady state lands
-- the camera on an exact whole-pixel-per-step pace with no beat.
function Camera.update(cam, player, world, dt)
  -- the render pass eases the camera between its previous and current
  -- positions (alpha from the accumulator); stamped before any motion
  cam._rx, cam._ry = cam.x, cam.y

  local vw, vh = config.view.width, config.view.height
  local tx = player.x + player.w/2 - vw/2
  local ty = player.y + player.h/2 - vh/2
  tx, ty = Camera.clamp(tx, ty, world)
  local ride_dx, ride_dy = 0, 0
  if player.ride and cam.ptx then
    ride_dx = tx - cam.ptx
    ride_dy = ty - cam.pty
  end
  cam.ptx, cam.pty = tx, ty
  local f = 1 - (1 - config.camera.follow) ^ dt
  cam.x = cam.x + (tx - cam.x) * f + ride_dx * (1 - f)
  cam.y = cam.y + (ty - cam.y) * f + ride_dy * (1 - f)
  -- shake/thud: random jitter re-rolled every step on top of the
  -- clamped follow position, decaying linearly to nothing (the follow
  -- absorbs the offset, so the shake self-corrects as it decays).
  -- Each kick carries its own decay length: blasts ride shake_steps,
  -- thuds ride thud_steps (the shorter decay).
  if cam.shake_t and cam.shake_t > 0 then
    local k = math.min(1, cam.shake_t / (cam.shake_len or config.camera.shake_steps))
    local s = (cam.shake_s or 0) * k
    cam.x = cam.x + (math.random() * 2 - 1) * s
    cam.y = cam.y + (math.random() * 2 - 1) * s
    cam.shake_t = cam.shake_t - dt
    if cam.shake_t <= 0 then
      cam.shake_t, cam.shake_s, cam.shake_len = nil, nil, nil
    end
  end
end

return Camera
