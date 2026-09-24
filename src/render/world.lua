-- World rendering (everything except the player, which is drawn last):
-- map tiles, interactables, particles, enemies, enemy arrows and the
-- player's arrows.
--
-- All functions read shared state through ctx: {config, world, ents, cam}.
-- Pure read: nothing here mutates game state.

local config = require("src.config")
local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Arrows = require("src.arrows")

local Render = {}

local pcol = Palette.rgb

-- Vector primitives are drawn at 2x to match the 2x2-upscaled sheet: dots
-- are 2x2 pixel blocks, lines 2px thick, so they keep the size they had on
-- the 240x160 canvas.
local function dot(x, y)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), 2, 2)
end

-- ==== terrain ====

-- The visible tile rect, top-left corner in tiles.
local function cam_tiles(cam)
  local tw = config.tile_size
  return math.floor(cam.x / tw), math.floor(cam.y / tw),
    config.view.width / tw, config.view.height / tw
end

local function draw_map(ctx)
  local cam, world = ctx.cam, ctx.world
  local tw = config.tile_size
  local vw, vh = config.view.width, config.view.height
  local mx = math.floor(cam.x / tw)
  local my = math.floor(cam.y / tw)
  love.graphics.setColor(1, 1, 1, 1)
  local cur_alpha = 1
  for r = my, my + vh/tw do
    for c = mx, mx + vw/tw + 1 do
      local t = world:tile(c, r)
      if t ~= 0 then
        -- non-solid phase tiles render translucent (draw alpha only
        -- changes when it has to, to keep the visible-tile loop cheap)
        local alpha = (world:is_phase(t) and not world.phase_solid)
          and config.phase.alpha or 1
        if alpha ~= cur_alpha then
          love.graphics.setColor(1, 1, 1, alpha)
          cur_alpha = alpha
        end
        love.graphics.draw(Sprites.sheet(), Sprites.quad(t), c*tw, r*tw)
      end
    end
  end
  if cur_alpha ~= 1 then love.graphics.setColor(1, 1, 1, 1) end
end

-- ==== interactables ====

local function draw_interactables(ctx)
  local ents = ctx.ents
  local tiles = ctx.tiles
  for _, k in ipairs(ents.keys) do
    if not k.taken then Sprites.draw(k.spr or tiles.key, k.x, k.y, false, k.rot) end
  end
  for _, l in ipairs(ents.locks) do
    if not l.triggered then Sprites.draw(l.spr or tiles.lock, l.x, l.y, false, l.rot) end
  end
  for _, d in ipairs(ents.doors) do
    if not d.open then Sprites.draw(d.spr or tiles.door, d.x, d.y, false, d.rot) end
  end
  for _, s in ipairs(ents.switches) do
    Sprites.draw(s.on and (s.spr + 1) or s.spr, s.x, s.y, false, s.rot)
  end
  for _, s in ipairs(ents.springs) do
    Sprites.draw(s.ext and tiles.spring_ext or (s.spr or tiles.spring),
      s.x, s.y, false, s.rot)
  end
  for _, w in ipairs(ents.winches) do
    Sprites.draw(w.spr or tiles.winch, w.x, w.y, false, w.rot)
  end
  for _, e in ipairs(ents.exits) do
    Sprites.draw(e.spr or tiles.exit, e.x, e.y, false, e.rot)
  end
  for _, cp in ipairs(ents.checkpoints) do
    Sprites.draw(cp.spr or tiles.checkpoint, cp.x, cp.y, false, cp.rot)
  end
end

-- ==== particles ====

local function draw_particles(ctx)
  for _, pt in ipairs(ctx.ents.particles) do
    love.graphics.setColor(pcol(pt.col or 8))
    -- particles default to the 2x2 dot; shards carry their own chunk
    -- size so the debris reads bigger than the spray around it
    local s = pt.s or 2
    love.graphics.rectangle("fill", math.floor(pt.x), math.floor(pt.y), s, s)
  end
end

-- ==== enemies ====

local function draw_enemies(ctx)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local ents, tiles = ctx.ents, ctx.tiles
  for _, e in ipairs(ents.enemies) do
    Sprites.draw(e.spr or ((e.type == "melee") and tiles.melee or tiles.archer),
      e.x, e.y, e.facing < 0, e.rot)
  end
end

-- ==== enemy arrows ====

local function draw_e_arrows(ctx)
  for _, a in ipairs(ctx.ents.e_arrows) do
    if a.active then
      local x, y = math.floor(a.x), math.floor(a.y)
      local len = math.sqrt(a.vx*a.vx + a.vy*a.vy)
      if len > 0 then
        love.graphics.setColor(pcol(8))  -- enemy arrows are red
        love.graphics.line(x, y,
          x - math.floor((a.vx/len)*6), y - math.floor((a.vy/len)*6))
        love.graphics.setColor(pcol(7))
        dot(x, y)
      end
    end
  end
end

-- ==== archer aims ====

-- An aiming archer shows its ballistic arc, like the player's aim
-- preview: a short direction line from the eye, then dots along the
-- solved trajectory (stopping where terrain would block the arrow).
local function draw_archer_aims(ctx)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  local shaft = config.arrows.colour
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "archer" and e.state == "aim" and e.aim_vx then
      local ex, ey = math.floor(e.x + e.w/2), math.floor(e.y + e.h/2)
      local len = math.sqrt(e.aim_vx*e.aim_vx + e.aim_vy*e.aim_vy)
      if len > 0 then
        local ux, uy = e.aim_vx/len, e.aim_vy/len
        love.graphics.setColor(pcol(shaft))
        love.graphics.line(ex, ey, ex + math.floor(ux*16), ey + math.floor(uy*16))
        local path = Arrows.simulate_path(ctx.world, ex, ey, e.aim_vx, e.aim_vy, {
          target = {x = e.aim_tx, y = e.aim_ty},
          max_frames = 120,
        })
        for _, pt in ipairs(path.points) do
          dot(pt.x, pt.y)
        end
      end
    end
  end
end

-- ==== laser riflemen ====

-- An aiming laser telegraphs a blinking red sight line locked onto the
-- direction it solved when the aim began (the flash and the beam that
-- follows share one vector); a firing laser shows its live beam: a thick
-- red ribbon (two outer lines) around a hot white core, from the muzzle
-- out to the wall it stops at. Vector primitives draw 2px thick, so the
-- offsets fake the extra width without transforming the pixel canvas.
local function draw_lasers(ctx)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "laser" then
      local ex, ey = math.floor(e.x + e.w/2), math.floor(e.y + e.h/2)
      if e.beam then
        local b = e.beam
        local tx = ex + math.floor(b.dx * b.len)
        local ty = ey + math.floor(b.dy * b.len)
        local ox, oy = math.floor(-b.dy * 2), math.floor(b.dx * 2)
        love.graphics.setColor(pcol(8))
        love.graphics.line(ex + ox, ey + oy, tx + ox, ty + oy)
        love.graphics.line(ex - ox, ey - oy, tx - ox, ty - oy)
        love.graphics.setColor(pcol(7))
        love.graphics.line(ex, ey, tx, ty)
      elseif e.state == "aim" and e.aim_dx and e.aim_len then
        -- the sight blinks on and off while the shot charges, pinned to
        -- the locked fire direction
        local phase = math.floor((cfg.laser_sight_steps - e.aim_t)
          / cfg.laser_sight_blink) % 2
        if phase == 0 then
          love.graphics.setColor(pcol(8))
          love.graphics.line(ex, ey,
            math.floor(ex + e.aim_dx * e.aim_len),
            math.floor(ey + e.aim_dy * e.aim_len))
        end
      end
    end
  end
end

-- ==== rocketeers ====

-- An aiming rocketeer telegraphs with a blinking red warning of dotted
-- sparks rising from its head: the shot goes up, so the telegraph does
-- too (same blink math as the laser sight).
local function draw_rocketeer_aims(ctx)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "rocketeer" and e.state == "aim" then
      local phase = math.floor((cfg.rocket_aim_steps - e.aim_t)
        / cfg.rocket_sight_blink) % 2
      if phase == 0 then
        local ex = math.floor(e.x + e.w/2)
        local top = math.floor(e.y)
        love.graphics.setColor(pcol(8))
        for i = 0, 3 do dot(ex, top - 2 - i*3) end
      end
    end
  end
end

-- ==== bombers ====

-- An aiming bomber telegraphs with a blinking orange dot held above
-- its head (the raised bomb) around a flickering white fuse spark,
-- same blink math as the other telegraphs.
local function draw_bomber_aims(ctx)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "bomber" and e.state == "aim" then
      local phase = math.floor((cfg.bomber_aim_steps - e.aim_t)
        / cfg.bomber_sight_blink) % 2
      if phase == 0 then
        local ex = math.floor(e.x + e.w/2)
        local top = math.floor(e.y)
        love.graphics.setColor(pcol(9))
        dot(ex, top - 5)
        love.graphics.setColor(pcol(7))
        dot(ex + 2, top - 8)
      end
    end
  end
end

-- ==== rockets ====

-- Rockets draw fat and readable: a thick red body (two outer lines
-- around a hot white core, laser-beam style) with a 3x3 white nose
-- cone and a flickering orange exhaust, oriented by the rocket's
-- heading (a hovering rocket hangs nose-up). The smoke trail itself is
-- particles.
local function draw_rockets(ctx)
  for _, r in ipairs(ctx.ents.rockets) do
    if r.active then
      local x, y = math.floor(r.x), math.floor(r.y)
      local hx, hy = r.hx or 0, r.hy or -1
      -- exhaust flame flickers behind the tail
      love.graphics.setColor(pcol(9))
      love.graphics.line(x - math.floor(hx*14), y - math.floor(hy*14),
        x - math.floor(hx*9), y - math.floor(hy*9))
      -- thick body: nose at the front, tail behind
      local nx, ny = x + math.floor(hx*4), y + math.floor(hy*4)
      local tx, ty = x - math.floor(hx*8), y - math.floor(hy*8)
      local ox, oy = math.floor(-hy * 2), math.floor(hx * 2)
      love.graphics.setColor(pcol(8))
      love.graphics.line(nx + ox, ny + oy, tx + ox, ty + oy)
      love.graphics.line(nx - ox, ny - oy, tx - ox, ty - oy)
      love.graphics.setColor(pcol(7))
      love.graphics.line(nx, ny, tx, ty)
      dot(nx + math.floor(hx*2), ny + math.floor(hy*2))
    end
  end
end

-- ==== bombs ====

-- A thrown bomb draws as a small round grenade: a 6px red body with a
-- white fuse spark that blinks as the fuse burns down.
local function draw_bombs(ctx)
  for _, b in ipairs(ctx.ents.bombs) do
    if b.active then
      local x, y = math.floor(b.x), math.floor(b.y)
      love.graphics.setColor(pcol(8))
      love.graphics.circle("fill", x, y, 3)
      love.graphics.setColor(pcol(7))
      if math.floor(b.fuse / 2) % 2 == 0 then
        dot(x + 3, y - 3)
      end
    end
  end
end

-- ==== shockwaves ====

-- A shockwave draws as its front: a semicircular arc of dots opening
-- along the travel direction (the 180-degree cone the sim collides
-- with). The nose of the front is hot white, the flanks the wave's
-- colour, and the arc grows with the wave (the radius is simulated
-- state). Parametrized trig-free: a point on the arc is
-- centre + r * (heading * sqrt(1-t^2) + perpendicular * t) for t in
-- -1..1.
local function draw_shockwaves(ctx)
  local cfg = config.shockwave
  for _, w in ipairs(ctx.ents.shockwaves) do
    if w.active then
      local len = math.sqrt(w.vx*w.vx + w.vy*w.vy)
      if len > 0 then
        local fx, fy = w.vx/len, w.vy/len
        local px, py = -fy, fx
        local steps = math.max(6, math.floor(w.r * 2))
        for i = 0, steps do
          local t = (i / steps) * 2 - 1
          local s = math.sqrt(1 - t*t)
          love.graphics.setColor(pcol(math.abs(t) < 0.5 and 7 or cfg.colour))
          dot(w.x + (fx * s + px * t) * w.r,
              w.y + (fy * s + py * t) * w.r)
        end
      end
    end
  end
end

-- ==== explosions ====

-- A detonation flash: an orange ring of dots expanding out to the
-- blast radius over boom_frames, around a white core while it is young.
-- Each boom carries the radius its blast used (rockets and thrown
-- bombs differ).
local function draw_booms(ctx)
  local cfg = config.enemies
  for _, b in ipairs(ctx.ents.booms) do
    local f = 1 - math.max(0, b.t) / cfg.boom_frames  -- 0..1 growth
    local rad = 4 + ((b.r or cfg.rocket_blast_radius) - 4) * f
    local steps = math.max(10, math.floor(rad))
    love.graphics.setColor(pcol(9))
    for i = 0, steps - 1 do
      local a = i / steps * math.pi * 2
      dot(b.x + math.cos(a) * rad, b.y + math.sin(a) * rad)
    end
    if f < 0.5 then
      love.graphics.setColor(pcol(7))
      love.graphics.circle("fill", math.floor(b.x), math.floor(b.y), 3 + f * 10)
    end
  end
end

-- ==== player arrows ====

-- Player arrows draw a size up from the enemy darts: a 9px shaft with a
-- 3x3 white tip (bigger than the 2x2 dots elsewhere, so your own shots
-- read clearly at a glance, without bloating into a bolt).
local function arrow_tip(x, y)
  love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y) - 1, 3, 3)
end

local ARROW_SHAFT = 9

local function draw_arrows(ctx)
  for _, a in ipairs(ctx.ents.arrows) do
    if a.active then
      local x, y = math.floor(a.x), math.floor(a.y)
      if a.stuck then
        love.graphics.setColor(pcol(7))
        arrow_tip(x, y)
        love.graphics.setColor(pcol(config.arrows.colour))
        love.graphics.line(x, y,
          x - math.floor(a.sdx*12), y - math.floor(a.sdy*12))
      elseif a.dying then
        -- spin-out: shaft whirling around its centre, tip leading
        local ca = math.floor(math.cos(a.spin) * 5)
        local sa = math.floor(math.sin(a.spin) * 5)
        love.graphics.setColor(pcol(config.arrows.colour))
        love.graphics.line(x - ca, y - sa, x + ca, y + sa)
        love.graphics.setColor(pcol(7))
        arrow_tip(x + ca, y + sa)
      else
        local len = math.sqrt(a.vx*a.vx + a.vy*a.vy)
        if len > 0 then
          local hx, hy = a.vx/len, a.vy/len
          love.graphics.setColor(pcol(config.arrows.colour))
          love.graphics.line(x, y,
            x - math.floor((a.vx/len)*ARROW_SHAFT),
            y - math.floor((a.vy/len)*ARROW_SHAFT))
          if a.kind == "bomb" then
            -- bomb arrows trade the white tip for a red bulb with a
            -- blinking fuse spark riding just behind it
            love.graphics.setColor(pcol(8))
            love.graphics.circle("fill",
              x + math.floor(hx*2), y + math.floor(hy*2), 3)
            if math.floor(a.traveled / 2) % 2 == 0 then
              love.graphics.setColor(pcol(7))
              dot(x + math.floor(hx*6), y + math.floor(hy*6))
            end
          else
            love.graphics.setColor(pcol(7))
            arrow_tip(x, y)
          end
        end
      end
      if a.key then Sprites.draw(ctx.tiles.key, x - 8, y - 8) end
    end
  end
end

-- ==== rope ====

-- The attached rope: a line from the anchored arrow's tip to the player
-- centre, drawn under the player sprite.
local function draw_ropes(ctx)
  local p = ctx.player
  -- the winch's line: from the winch centre to the player while the
  -- motor reels them in (the arrow itself was consumed on capture)
  if p.winch and p.winch.ent then
    local w = p.winch.ent
    love.graphics.setColor(pcol(config.rope.colour))
    love.graphics.line(w.x + config.tile_size/2, w.y + config.tile_size/2,
      math.floor(p.x + p.w/2), math.floor(p.y + p.h/2))
    return
  end
  local rope = p.rope
  if not rope or not rope.arrow or not rope.arrow.active then return end
  local a = rope.arrow
  love.graphics.setColor(pcol(config.rope.colour))
  love.graphics.line(a.x, a.y,
    math.floor(ctx.player.x + ctx.player.w/2),
    math.floor(ctx.player.y + ctx.player.h/2))
end

-- The full world pass, in draw order (player drawn separately on top;
-- the foreground overlay renders after them, see render/blit.lua).
function Render.world(ctx)
  draw_map(ctx)
  draw_interactables(ctx)
  draw_particles(ctx)
  draw_enemies(ctx)
  draw_archer_aims(ctx)
  draw_lasers(ctx)
  draw_rocketeer_aims(ctx)
  draw_bomber_aims(ctx)
  draw_e_arrows(ctx)
  draw_rockets(ctx)
  draw_bombs(ctx)
  draw_shockwaves(ctx)
  draw_arrows(ctx)
  draw_booms(ctx)
  draw_ropes(ctx)
end

-- Foreground overlay pass: drawn after the player so buildings and
-- hidden spaces cover the world. The active room fades as a whole
-- (World:foreground_step drives that room's alpha to 0 while the player
-- walks behind any of it, so their avatar stays visible, and back to 1
-- after); tiles beyond the active room never draw.
function Render.foreground(ctx)
  local world = ctx.world
  if not world.fg_map then return end
  local alpha = world.fg_alpha[world.active_room and world.active_room.i or 0] or 1
  if alpha <= 0 then return end
  local mx, my, vw_t, vh_t = cam_tiles(ctx.cam)
  local tw = config.tile_size
  local room = world.active_room
  love.graphics.setColor(1, 1, 1, alpha)
  for r = my, my + vh_t do
    for c = mx, mx + vw_t + 1 do
      local t = world:fg_tile(c, r)
      if t ~= 0
      and (not room or (c*tw >= room.x and c*tw < room.x + room.w
                   and r*tw >= room.y and r*tw < room.y + room.h)) then
        love.graphics.draw(Sprites.sheet(), Sprites.quad(t), c*tw, r*tw)
      end
    end
  end
  if alpha ~= 1 then love.graphics.setColor(1, 1, 1, 1) end
end

return Render
