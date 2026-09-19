-- Game orchestrator: owns the shared state (world, entities, player,
-- camera, input), runs the fixed-timestep 30hz simulation, the controls
-- panel mode, and renders via src/render/blit.lua.
--
-- Simulation is a fixed 1/30s timestep with an accumulator. Each step
-- advances world time by ctx.dt steps (1 normally; reduced while aiming
-- for smooth slow motion). Held input is polled once per rendered frame
-- (src/input.lua); press edges are evaluated once per sim step.

local config   = require("src.config")
local Input    = require("src.input")
local tiled    = require("src.tiled")
local World    = require("src.world")
local Level    = require("src.level")
local Camera   = require("src.camera")
local Player   = require("src.player")
local Arrows   = require("src.arrows")
local Enemies  = require("src.enemies")
local Rockets  = require("src.rockets")
local Particles = require("src.particles")
local Interactables = require("src.interactables")
local Sprites  = require("src.sprites")
local Blit     = require("src.render.blit")

local Game = {}
Game.__index = Game

function Game.new()
  local self = setmetatable({}, Game)
  self.input      = Input.new()
  self.menu_open  = false  -- test menu panel (m / tab / start)
  self.menu_sel   = 1      -- highlighted menu row (1..3)
  self.settings   = { no_puzzle = false, invincible = false }
  self.step_count = 0
  self.acc        = 0
  self.step_dt    = 1 / config.sim.rate
  self.window_display = nil  -- display the window last fitted (see fit_window)
  return self
end

function Game:load()
  math.randomseed(os.time())
  Sprites.init(love.graphics.newImage("spritesheet.png"))
  Blit.init()

  -- level: Tiled JSON map (flags/kinds/slopes come from tileset properties)
  local level = tiled.load(config.map_file)
  local ents, tiles = Level.build(level, config)
  self.world = World.new(level, ents, config.tile_size)
  self.ents  = ents
  self.tiles = tiles
  self.cam   = Camera.new()

  -- The shared context every system reads; `die` routes player deaths to
  -- Player.die and `hurt` routes damage to Player.hurt (systems never
  -- require src/player.lua for those paths).
  self.player = Player.new(nil)
  self.ctx = {
    config = config,
    input  = self.input,
    world  = self.world,
    ents   = ents,
    tiles  = tiles,
    cam    = self.cam,
    player = self.player,
    settings = self.settings,  -- test-menu toggles (see menu_step)
    menu   = self,             -- menu panel reads menu_sel/settings
    die    = Player.die,
    hurt   = Player.hurt,
    dt     = 1,  -- world-time scale of the current step (Game:step sets it)
  }

  Player.reset(self.player, ents.spawn_points, self.cam, self.world)
end

-- ==== window fitting ====

-- Keeps the window at an integer multiple of the 480x320 view that fits
-- the desktop it is currently on. Monitors differ in resolution and DPI
-- scale: a window sized for one screen gets clamped by the window
-- manager on the next (fractionally scaling the framebuffer -> blurry
-- pixels, plus letterbox bars). Re-fits whenever the window lands on a
-- different display, so dragging between monitors stays sharp and the
-- window always fills its frame exactly (no bars while windowed).
-- No-op in fullscreen and in the headless test harness (no love.window).
function Game:fit_window()
  if not love.window or love.window.getFullscreen() then return end
  local _, _, display = love.window.getPosition()
  if display == self.window_display then return end
  self.window_display = display
  local dw, dh = love.window.getDesktopDimensions(display)
  local scale = math.floor(math.min(
    (dw - 16) / config.view.width, (dh - 48) / config.view.height))
  scale = math.max(1, math.min(config.window.scale, scale))
  local w, h = config.view.width * scale, config.view.height * scale
  local _, _, flags = love.window.getMode()
  love.window.setMode(w, h, flags)
end

-- ==== simulation ====

-- One 30hz tick: aiming/firing first, then a full physics pass every
-- step. The step advances world time by dt steps (1 normally; 1 /
-- aiming.slow_motion_steps while aiming, so slow motion runs every
-- physics pass at a steady cadence instead of skipping passes).
-- Everything world-time based (integrators, timers) scales with ctx.dt;
-- real-time things (input cadence, bow turning) do not.
function Game:step()
  local ctx = self.ctx
  self.step_count = self.step_count + 1
  ctx.input:step()

  Player.arrow_step(ctx)
  Player.aim_step(ctx)

  local dt = not ctx.input:down("aim")
           and 1
           or (1 / config.aiming.slow_motion_steps)
  ctx.dt = dt
  Player.physics(ctx)
  Arrows.update(ctx)
  if config.enemies.enabled then
    Enemies.update(ctx)
    Arrows.update_enemy_arrows(ctx)
    Rockets.update(ctx)
  end
  Particles.update(ctx.ents, dt)
  Interactables.update_springs(ctx.ents, dt)
  Camera.update(ctx.cam, ctx.player, ctx.world, dt)
end

-- Toggles all enemies on/off (test-menu row 3). Turning them off also
-- disarms anything in flight or mid-shot: enemy arrows vanish, archers
-- drop back to patrol, live beams go out and chasing/searching melee
-- calm down, so nothing resumes mid-shot when the toggle comes back
-- on. Disabled enemies are also not drawn.
function Game:toggle_enemies()
  config.enemies.enabled = not config.enemies.enabled
  if not config.enemies.enabled then
    self.ents.e_arrows = {}
    self.ents.rockets  = {}
    self.ents.booms    = {}
    for _, e in ipairs(self.ents.enemies) do
      if e.type == "archer" then
        e.state = "patrol"
        e.volley = nil
        e.aim_vx, e.aim_vy = nil, nil
        e.suppress_t = nil
      elseif e.type == "laser" then
        e.state = "patrol"
        e.beam = nil
        e.aim_dx, e.aim_dy, e.aim_len = nil, nil, nil
        e.suppress_t = nil
        e.burst = nil
      elseif e.type == "rocketeer" then
        e.state = "patrol"
        e.suppress_t = nil
        e.burst = nil
      else
        e.state = "patrol"
      end
    end
  end
end

-- One 30hz tick of the test menu (game world is paused). Up/down move
-- the selection, c/X toggles the highlighted row, aim/jump closes.
function Game:menu_step()
  local ctx = self.ctx
  ctx.input:step()
  local rows = 3
  if ctx.input:pressed("up") then
    self.menu_sel = ((self.menu_sel - 2) % rows) + 1
  end
  if ctx.input:pressed("down") then
    self.menu_sel = (self.menu_sel % rows) + 1
  end
  if ctx.input:pressed("swap") then
    if self.menu_sel == 1 then self:toggle_puzzle()
    elseif self.menu_sel == 2 then self:toggle_invincibility()
    else self:toggle_enemies() end
  end
  if ctx.input:pressed("aim") or ctx.input:pressed("jump") then
    self.menu_open = false
  end
end

-- Test-menu toggles.

-- Hides every key, lock and door (they stop rendering, stop blocking,
-- stop being picked up or triggered). Toggling back restores each piece
-- to its pre-toggle state (consumed keys stay consumed).
function Game:toggle_puzzle()
  self.settings.no_puzzle = not self.settings.no_puzzle
  Interactables.set_puzzle_disabled(
    self.ents, self.player, self.settings.no_puzzle)
end

function Game:toggle_invincibility()
  self.settings.invincible = not self.settings.invincible
end

function Game:update(dt)
  self:fit_window()
  self.input:poll()
  -- clamp dt so tab-through / slow frames never produce a huge catchup
  self.acc = math.min(self.acc + dt, config.sim.max_accumulator)
  while self.acc >= self.step_dt do
    self.acc = self.acc - self.step_dt
    if self.menu_open then self:menu_step() else self:step() end
  end
end

-- ==== rendering ====

function Game:draw()
  Blit.render(self.ctx, self.menu_open)
end

-- ==== input callbacks ====

function Game:keypressed(key, isrepeat)
  if key == "escape" then love.event.quit() return end
  -- fullscreen toggle (F11): desktop mode, so the monitor keeps its
  -- resolution and the blit letterboxes with integer scaling
  if not isrepeat and key == config.window.fullscreen_key and love.window then
    love.window.setFullscreen(not love.window.getFullscreen())
  end
  -- latch presses immediately so sub-frame taps are never lost; OS key
  -- repeats are ignored (the 30hz input:step provides pico-8-style repeat)
  self.input:latch_key(key, isrepeat)
  -- m / tab toggle the test menu (start does it on gamepads)
  if not isrepeat and (key == "m" or key == "tab") then
    self.menu_open = not self.menu_open
  end
end

function Game:gamepadpressed(button)
  if button == "start" then  -- start toggles the test menu
    self.menu_open = not self.menu_open
    return
  end
  if button == "back" then love.event.quit() return end
  self.input:latch_gamepad(button)
end

function Game:focus(focused)
  if not focused then
    -- window lost focus: drop all input so no key stays stuck
    self.input:reset()
  end
end

-- ==== test support ====

-- State snapshot for the headless harness (tests/run.lua); must match the
-- frozen legacy oracle's format exactly.
function Game:snapshot(step)
  local ctx = self.ctx
  local function trace_arrow(a)
    return {
      x=a.x, y=a.y, vx=a.vx, vy=a.vy, active=a.active, stuck=a.stuck,
      bounced=a.bounced, dying=a.dying, spin=a.spin, lt=a.lt,
      grab_cd=a.grab_cd, sdx=a.sdx, sdy=a.sdy, face=a.face,
      on_slope=a.on_slope, kind=a.kind, traveled=a.traveled,
      rope_taken=a.rope_taken,
      key=a.key and (a.key.g or "ungrouped") or false,
    }
  end
  local ents = ctx.ents
  local arr, earr, ene = {}, {}, {}
  for _, a in ipairs(ents.arrows) do arr[#arr+1] = trace_arrow(a) end
  for _, a in ipairs(ents.e_arrows) do
    earr[#earr+1] = {x=a.x, y=a.y, vx=a.vx, vy=a.vy, active=a.active}
  end
  for _, e in ipairs(ents.enemies) do
    ene[#ene+1] = {x=e.x, y=e.y, vx=e.vx, vy=e.vy, gr=e.gr,
      facing=e.facing, type=e.type, shoot_cd=e.shoot_cd}
  end
  local ks, ls, ds, sws, sps = {}, {}, {}, {}, {}
  for _, k in ipairs(ents.keys) do ks[#ks+1] = {taken=k.taken, g=k.g} end
  for _, l in ipairs(ents.locks) do ls[#ls+1] = {triggered=l.triggered, g=l.g} end
  for _, d in ipairs(ents.doors) do ds[#ds+1] = {open=d.open, g=d.g} end
  for _, s in ipairs(ents.switches) do sws[#sws+1] = {on=s.on, g=s.g} end
  for _, s in ipairs(ents.springs) do sps[#sps+1] = {ext=s.ext, g=s.g} end
  local run_frame, run_tick = Player.run_state()
  return {
    step = step,
    player = {
      x=self.player.x, y=self.player.y, vx=self.player.vx, vy=self.player.vy,
      w=self.player.w, h=self.player.h, gr=self.player.gr,
      facing=self.player.facing, coy=self.player.coy, jbuf=self.player.jbuf,
      fr=self.player.fr, j_frames=self.player.j_frames,
      aim_angle=self.player.aim_angle, aim_power=self.player.aim_power,
      was_aiming=self.player.was_aiming, aimed_down=self.player.aimed_down,
      prev_gr=self.player.prev_gr, land_frames=self.player.land_frames,
      key=self.player.key and (self.player.key.g or "ungrouped") or false,
      hp=self.player.hp, invuln=self.player.invuln,
      arrow_kind=self.player.arrow_kind,
      rope=self.player.rope and self.player.rope.length or false,
    },
    cam = {x=self.cam.x, y=self.cam.y},
    arrows = arr,
    e_arrows = earr,
    enemies = ene,
    keys = ks, locks = ls, doors = ds, switches = sws, springs = sps,
    phase = self.world.phase_solid,
    particles = #ents.particles,
    run_frame = run_frame, run_tick = run_tick,
  }
end

return Game
