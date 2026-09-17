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
end

-- ==== particles ====

local function draw_particles(ctx)
  for _, pt in ipairs(ctx.ents.particles) do
    love.graphics.setColor(pcol(pt.col or 8))
    dot(pt.x, pt.y)
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
          love.graphics.setColor(pcol(config.arrows.colour))
          love.graphics.line(x, y,
            x - math.floor((a.vx/len)*ARROW_SHAFT),
            y - math.floor((a.vy/len)*ARROW_SHAFT))
          love.graphics.setColor(pcol(7))
          arrow_tip(x, y)
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

-- The full world pass, in draw order (player drawn separately on top).
function Render.world(ctx)
  draw_map(ctx)
  draw_interactables(ctx)
  draw_particles(ctx)
  draw_enemies(ctx)
  draw_archer_aims(ctx)
  draw_e_arrows(ctx)
  draw_arrows(ctx)
  draw_ropes(ctx)
end

return Render
