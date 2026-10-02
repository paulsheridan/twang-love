-- World rendering (everything except the player, which is drawn last):
-- embedded arrows, map tiles, interactables, particles, enemies, enemy
-- arrows and the player's arrows.
--
-- All functions read shared state through ctx: {config, world, ents, cam}.
-- Movable entities draw at their eased position (Util.render_pos): the
-- sim stamps each one's previous position every tick, and the draw
-- pass's alpha (0..1) eases between the last two sim states so 60hz
-- physics presents smoothly on any refresh rate.
-- Pure read: nothing here mutates game state.
local config = require("src.config")
local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Arrows = require("src.arrows")
local Util   = require("src.util")

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
      local rec = world:tile_record(world:tile(c, r))
      local q = rec and Sprites.quad(rec)
      if q then
        -- non-solid phase tiles render translucent (draw alpha only
        -- changes when it has to, to keep the visible-tile loop cheap)
        local alpha = (rec.phase and not world.phase_solid)
          and config.phase.alpha or 1
        if alpha ~= cur_alpha then
          love.graphics.setColor(1, 1, 1, alpha)
          cur_alpha = alpha
        end
        love.graphics.draw(Sprites.image(rec.image), q, c*tw, r*tw)
      end
    end
  end
  if cur_alpha ~= 1 then love.graphics.setColor(1, 1, 1, 1) end
end

-- ==== interactables ====

-- Where to put a sprite that is bigger than the block it belongs to (a
-- 32x32 device cell on its 16px block): centred across the block and
-- standing on its bottom edge, so the device sits on the same spot and
-- the same floor whatever its cell size, with the extra room above it
-- where an updraft's column is drawn. A 16x16 cell is unaffected.
local function grounded_art(art, x, y)
  if not art then return x, y end
  return x - math.max(0, (art.w - config.art_size) / 2),
         y - math.max(0, art.h - config.art_size)
end

-- The pusher variants' direction hints, drawn over the device sprite so
-- the launch they promise is readable at a glance:
--
--   updraft: three short straight-up ticks over the tile (the column
--   drag above it);
--   outdraft: a three-tick fan splayed 0/±45 degrees, tracing the cone
--   the drain covers.
--
-- The ticks are anchored to the block, not the sprite, so a device drawn
-- taller than its block keeps promising its launch from its own tile.
local function draw_pusher_ticks(pu)
  local cx = math.floor(pu.x + config.art_size/2)
  local top = math.floor(pu.y) - 2
  love.graphics.setColor(pcol(7))
  if pu.variant == "outdraft" then
    -- x offsets land the 2x2 dots on the fan legs (split around centre)
    local dxy = { {0,-4}, {3,-3}, {-3,-3} }
    for _, d in ipairs(dxy) do dot(cx + d[1] - 1, top + d[2]) end
  else
    for i = 0, 2 do dot(cx - 1, top - 2 - i*3) end
  end
end

-- Movers draw their sprite per covered tile (the block footprint), plus
-- a direction tick: a dot trail pointing the way the line runs (grey for
-- an auto cycler; an orange dot on the face of a parked trigger mover,
-- which lights the way it will run once struck).
local function draw_mover_ticks(m, bx, by)
  local cx = math.floor(bx + m.bw / 2)
  local cy = math.floor(by + m.bh / 2)
  if m.mode == "trigger" and m.state == "rest" then
    -- parked trigger: a warm dot (it waits for you)
    love.graphics.setColor(pcol(9))
    dot(cx - 1, cy - 1)
    return
  end
  -- moving (or auto): grey dots trailing along the travel axis ahead
  love.graphics.setColor(pcol(7))
  local ddx, ddy = m.dirn * m.dx, m.dirn * m.dy
  for i = 1, 3 do
    dot(cx - 1 + math.floor(ddx * (i * 5)),
        cy - 1 + math.floor(ddy * (i * 5)))
  end
end

local function draw_interactables(ctx)
  local ents = ctx.ents
  for _, k in ipairs(ents.keys) do
    if not k.taken then Sprites.draw(k.art, k.x, k.y, false, k.rot) end
  end
  for _, l in ipairs(ents.locks) do
    if not l.triggered then Sprites.draw(l.art, l.x, l.y, false, l.rot) end
  end
  for _, d in ipairs(ents.doors) do
    if not d.open then Sprites.draw(d.art, d.x, d.y, false, d.rot) end
  end
  for _, s in ipairs(ents.switches) do
    Sprites.draw(s.on and s.art_on or s.art, s.x, s.y, false, s.rot)
  end
  for _, s in ipairs(ents.springs) do
    Sprites.draw(s.ext and s.art_ext or s.art, s.x, s.y, false, s.rot)
  end
  for _, gg in ipairs(ents.guns) do
    if not gg.taken then
      -- the dropped gun (placeholder art: a chunky dark slab with a red
      -- tip; sits on the ground like the key pickups)
      local gx, gy = math.floor(gg.x) + 2, math.floor(gg.y) + 8
      love.graphics.setColor(pcol(1))
      love.graphics.rectangle("fill", gx, gy, 10, 5)
      love.graphics.setColor(pcol(0))
      love.graphics.rectangle("fill", gx, gy + 5, 3, 3)
      love.graphics.setColor(pcol(8))
      love.graphics.rectangle("fill", gx + 9, gy, 3, 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  for _, w in ipairs(ents.winches) do
    Sprites.draw(w.art, w.x, w.y, false, w.rot)
  end
  for _, pu in ipairs(ents.pushers) do
    local ax, ay = grounded_art(pu.art, pu.x, pu.y)
    Sprites.draw(pu.art, ax, ay, false, pu.rot)
    draw_pusher_ticks(pu)
  end
  for _, m in ipairs(ents.movers) do
    -- the block draws its art per 16px art-cell region of the footprint
    -- (the block's box in art tiles), laid out from the block's LIVE
    -- pixel position — floored to whole pixels like every body, so the
    -- ride is smooth rather than popping cell to cell. A block smaller
    -- than one art cell scales the sprite down to fit it.
    -- the block's box lives on bx/by (not x/y): ease the box origin
    local bx = m._px and Util.lerp(m._px, m.bx, alpha or 1) or m.bx
    local by = m._py and Util.lerp(m._py, m.by, alpha or 1) or m.by
    local art = config.art_size
    local q, img = Sprites.quad(m.art), m.art and Sprites.image(m.art.image)
    if q and img then
      for gy = 0, math.ceil(m.bh / art) - 1 do
        for gx = 0, math.ceil(m.bw / art) - 1 do
          local wpx = math.min(art, m.bw - gx * art)
          local hpx = math.min(art, m.bh - gy * art)
          love.graphics.draw(img, q,
            math.floor(bx + gx * art), math.floor(by + gy * art),
            0, wpx / art, hpx / art)
        end
      end
    end
    draw_mover_ticks(m, bx, by)
  end
  for _, e in ipairs(ents.exits) do
    Sprites.draw(e.art, e.x, e.y, false, e.rot)
  end
  for _, cp in ipairs(ents.checkpoints) do
    Sprites.draw(cp.art, cp.x, cp.y, false, cp.rot)
  end
end

-- ==== particles ====

local function draw_particles(ctx, alpha)
  for _, pt in ipairs(ctx.ents.particles) do
    love.graphics.setColor(pcol(pt.col or 8))
    -- particles default to the 2x2 dot; shards carry their own chunk
    -- size so the debris reads bigger than the spray around it
    local s = pt.s or 2
    local x, y = Util.render_pos(pt, alpha)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), s, s)
  end
end

-- ==== enemies ====

local function draw_enemies(ctx, alpha)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local ents = ctx.ents
  for _, e in ipairs(ents.enemies) do
    local x, y = Util.render_pos(e, alpha)
    Sprites.draw(e.art, x, y, e.facing < 0, e.rot)
  end
end

-- ==== enemy arrows ====

local function draw_e_arrows(ctx, alpha)
  for _, a in ipairs(ctx.ents.e_arrows) do
    if a.active then
      local ex, ey = Util.render_pos(a, alpha)
      local x, y = math.floor(ex), math.floor(ey)
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
local function draw_archer_aims(ctx, alpha)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  local shaft = config.arrows.colour
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "archer" and e.state == "aim" and e.aim_vx then
      local sx, sy = Util.render_pos(e, alpha)
      local ex, ey = math.floor(sx + e.w/2), math.floor(sy + e.h/2)
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
local function draw_lasers(ctx, alpha)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "laser" then
      local sx, sy = Util.render_pos(e, alpha)
      local ex, ey = math.floor(sx + e.w/2), math.floor(sy + e.h/2)
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
local function draw_rocketeer_aims(ctx, alpha)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "rocketeer" and e.state == "aim" then
      local phase = math.floor((cfg.rocket_aim_steps - e.aim_t)
        / cfg.rocket_sight_blink) % 2
      if phase == 0 then
        local sx, sy = Util.render_pos(e, alpha)
        local ex = math.floor(sx + e.w/2)
        local top = math.floor(sy)
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
local function draw_bomber_aims(ctx, alpha)
  if not config.enemies.enabled then return end  -- toggled off: invisible
  local cfg = config.enemies
  for _, e in ipairs(ctx.ents.enemies) do
    if e.type == "bomber" and e.state == "aim" then
      local phase = math.floor((cfg.bomber_aim_steps - e.aim_t)
        / cfg.bomber_sight_blink) % 2
      if phase == 0 then
        local sx, sy = Util.render_pos(e, alpha)
        local ex = math.floor(sx + e.w/2)
        local top = math.floor(sy)
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
local function draw_rockets(ctx, alpha)
  for _, r in ipairs(ctx.ents.rockets) do
    if r.active then
      local rx, ry = Util.render_pos(r, alpha)
      local x, y = math.floor(rx), math.floor(ry)
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
local function draw_bombs(ctx, alpha)
  for _, b in ipairs(ctx.ents.bombs) do
    if b.active then
      local bx, by = Util.render_pos(b, alpha)
      local x, y = math.floor(bx), math.floor(by)
      love.graphics.setColor(pcol(8))
      love.graphics.circle("fill", x, y, 3)
      love.graphics.setColor(pcol(7))
      if math.floor(b.fuse / 2) % 2 == 0 then
        dot(x + 3, y - 3)
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
local STUCK_SHAFT = 12

-- The embedded arrow's shaft, drawn BUCKLED: the impact leaves it kinked
-- a little way back from the buried tip, so it draws as two segments
-- meeting at a point nudged sideways off the flight line. The kick
-- scales with how fast the arrow arrived (a soft tap lands dead
-- straight, a full-power shot visibly buckles) and is capped at
-- `arrows.bend_max_px` — a couple of pixels, just enough to read as
-- "struck hard", never a snapped shaft. Pure geometry off the arrow's
-- own state: `sdx`/`sdy` are its frozen heading and `vx`/`vy` are still
-- the impact velocity, so the sim never grows a field for this. Which
-- way it buckles rides the tile the arrow sits in, so neighbours kink
-- differently without the sim spending a random draw.
local function bent_shaft(x, y, a)
  local cfg = config.arrows
  local spd = math.sqrt(a.vx*a.vx + a.vy*a.vy)
  local kick = math.min(cfg.bend_max_px,
    math.max(0, spd - cfg.bend_speed) * cfg.bend_scale)
  local tw = config.tile_size
  local sign = (math.floor(a.x / tw) + math.floor(a.y / tw)) % 2 == 0
    and 1 or -1
  -- the kink: most of the way back down the shaft, offset along the
  -- heading's perpendicular
  local kx = x - a.sdx * STUCK_SHAFT * 0.6 - a.sdy * kick * sign
  local ky = y - a.sdy * STUCK_SHAFT * 0.6 + a.sdx * kick * sign
  love.graphics.line(math.floor(kx), math.floor(ky),
    math.floor(x - a.sdx*STUCK_SHAFT), math.floor(y - a.sdy*STUCK_SHAFT))
  love.graphics.line(math.floor(x), math.floor(y),
    math.floor(kx), math.floor(ky))
end

-- Embedded arrows get their own pass, drawn BEFORE the terrain (see
-- Render.world): the tip is buried in the surface, so the tiles have to
-- paint over that buried length and the arrow must not be visible in
-- front of the wall it is stuck into. Only the shaft shows, emerging.
local function draw_stuck_arrows(ctx, alpha)
  for _, a in ipairs(ctx.ents.arrows) do
    if a.active and a.stuck then
      local ax, ay = Util.render_pos(a, alpha)
      local x, y = math.floor(ax), math.floor(ay)
      love.graphics.setColor(pcol(7))
      arrow_tip(x, y)
      love.graphics.setColor(pcol(config.arrows.colour))
      bent_shaft(x, y, a)
    end
  end
end

local function draw_arrows(ctx, alpha)
  for _, a in ipairs(ctx.ents.arrows) do
    if a.active then
      local ax, ay = Util.render_pos(a, alpha)
      local x, y = math.floor(ax), math.floor(ay)
      -- a stuck arrow's shaft already drew, under the terrain; all that
      -- is left of it here is the key it carries, which must stay
      -- readable against the wall
      if not a.stuck then
        if a.dying then
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
            elseif a.kind == "gun" then
              -- the gun in flight: a chunky dark shell with a red tip
              -- (placeholder art, like the dropped pickup)
              love.graphics.setColor(pcol(1))
              love.graphics.rectangle("fill",
                x + math.floor(hx*3) - 2, y + math.floor(hy*3) - 2, 4, 4)
              love.graphics.setColor(pcol(8))
              dot(x + math.floor(hx*4), y + math.floor(hy*4))
            else
              love.graphics.setColor(pcol(7))
              arrow_tip(x, y)
            end
          end
        end
      end
      if a.key then Sprites.draw(ctx.art.key, x - 8, y - 8) end
    end
  end
end

-- ==== rope ====

-- The attached rope: a line from the anchored arrow's tip to the player
-- centre, drawn under the player sprite.
local function draw_ropes(ctx, alpha)
  local p = ctx.player
  -- the winch's line: from the winch centre to the player while the
  -- motor reels them in (the arrow itself was consumed on capture)
  if p.winch and p.winch.ent then
    local w = p.winch.ent
    love.graphics.setColor(pcol(config.rope.colour))
    local px, py = Util.render_pos(p, alpha)
    love.graphics.line(w.x + config.art_size/2, w.y + config.art_size/2,
      math.floor(px + p.w/2), math.floor(py + p.h/2))
    return
  end
  local rope = p.rope
  if not rope or not rope.arrow or not rope.arrow.active then return end
  local a = rope.arrow
  love.graphics.setColor(pcol(config.rope.colour))
  local px, py = Util.render_pos(ctx.player, alpha)
  -- the line starts at the anchor's SURFACE, not at its buried tip: the
  -- rope draws over the terrain, so anchoring at the tip would lay the
  -- first few px of line across the wall
  local e = config.arrows.embed_px
  love.graphics.line(a.x - (a.sdx or 0)*e, a.y - (a.sdy or 0)*e,
    math.floor(px + ctx.player.w/2),
    math.floor(py + ctx.player.h/2))
end

-- The full world pass, in draw order (player drawn separately on top;
-- the foreground overlay renders after them, see render/blit.lua).
-- Embedded arrows draw FIRST, under the terrain: their tips sink into
-- the surface they struck, so the tiles have to paint over the buried
-- length and the arrow must never read as floating in front of the wall
-- it is stuck into.
function Render.world(ctx, alpha)
  draw_stuck_arrows(ctx, alpha)
  draw_map(ctx)
  draw_interactables(ctx, alpha)
  draw_particles(ctx, alpha)
  draw_enemies(ctx, alpha)
  draw_archer_aims(ctx, alpha)
  draw_lasers(ctx, alpha)
  draw_rocketeer_aims(ctx, alpha)
  draw_bomber_aims(ctx, alpha)
  draw_e_arrows(ctx, alpha)
  draw_rockets(ctx, alpha)
  draw_bombs(ctx, alpha)
  draw_arrows(ctx, alpha)
  draw_booms(ctx)
  draw_ropes(ctx, alpha)
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
      local rec = world:tile_record(world:fg_tile(c, r))
      local q = rec and Sprites.quad(rec)
      if q
      and (not room or (c*tw >= room.x and c*tw < room.x + room.w
                   and r*tw >= room.y and r*tw < room.y + room.h)) then
        love.graphics.draw(Sprites.image(rec.image), q, c*tw, r*tw)
      end
    end
  end
  if alpha ~= 1 then love.graphics.setColor(1, 1, 1, 1) end
end

return Render
