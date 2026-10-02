-- Headless LÖVE stubs for the characterization harness (tests/run.lua).
--
-- Builds a sandbox environment in which an entry file (the frozen legacy
-- main.lua or the refactored main.lua) can run without a real LÖVE runtime.
-- Only the API surface the game touches is stubbed:
--
--   love.keyboard.isDown   -> driven by the scripted input state
--   love.joystick          -> no gamepads connected
--   love.event.quit        -> sets a flag the driver polls
--   love.graphics          -> inert dummies (image/canvas/quad objects)
--
-- love.filesystem is deliberately absent so tiled.lua falls back to io
-- reads, and os.time is pinned so the game's randomseed is deterministic.

local Harness = {}

-- Dummy object standing in for images and canvases.
local function dummy_image()
  return {
    setFilter = function() end,
    getWidth = function() return 256 end,
    getHeight = function() return 256 end,
  }
end

-- Builds the sandbox environment. `keys_down` (a name->bool map) is owned
-- by the driver and mutated between steps; `quit_flag` likewise.
function Harness.new_env(keys_down, quit_flag)
  local env = setmetatable({}, { __index = _G })

  -- Test hook registry; entry files register their trace function here.
  env.TWANG_TEST = {}

  -- Strict graphics stubs: drawing calls must be well-formed even though
  -- they render nothing. This lets the driver exercise the full draw path
  -- (rendering bugs otherwise escape the simulation-only trace).
  local function expect_numbers(prefix, ...)
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      if type(v) ~= "number" then
        error(prefix .. ": argument " .. i .. " should be a number, got "
          .. tostring(v), 3)
      end
    end
  end
  local graphics = {}
  -- Optional line capture, for tests that assert on drawn geometry
  -- (tests/arrows_test.lua reads the stuck arrow's shaft). Off unless a
  -- test hands TWANG_TEST.record_lines a sink table, so the long
  -- scripted trace runs pay nothing for it.
  local line_sink = nil
  graphics.newImage = function() return dummy_image() end
  graphics.newCanvas = function() return dummy_image() end
  graphics.newQuad = function() return {} end
  graphics.setFilter = function() end
  graphics.setColor = function(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
    or (a ~= nil and type(a) ~= "number") then
      error("setColor: expected RGBA numbers, got "
        .. tostring(r) .. ", " .. tostring(g) .. ", " .. tostring(b) .. ", "
        .. tostring(a), 2)
    end
  end
  graphics.line = function(x1, y1, x2, y2)
    expect_numbers("line", x1, y1, x2, y2)
    if line_sink then line_sink[#line_sink + 1] = {x1, y1, x2, y2} end
  end
  graphics.points = function(x, y) expect_numbers("points", x, y) end
  graphics.print = function(text, x, y)
    if type(text) ~= "string" then
      error("print: text must be a string", 2)
    end
    expect_numbers("print", x, y)
  end
  graphics.rectangle = function(mode, x, y, w, h)
    if mode ~= "fill" and mode ~= "line" then
      error("rectangle: mode must be 'fill' or 'line'", 2)
    end
    expect_numbers("rectangle", x, y, w, h)
  end
  graphics.circle = function(mode, x, y, r)
    if mode ~= "fill" and mode ~= "line" then
      error("circle: mode must be 'fill' or 'line'", 2)
    end
    expect_numbers("circle", x, y, r)
  end
  graphics.draw = function(image, ...)
    if type(image) ~= "table" then
      error("draw: first argument must be an image/canvas stub", 2)
    end
    -- Two calling conventions: draw(image, x, y, [rot, sx, sy]) and
    -- draw(sheet, quad, x, y, ...). Every argument after the first must
    -- be a number (position/scale/rotation) or a quad stub (table).
    local n = select("#", ...)
    if n < 2 then
      error("draw: expected at least image + 2 coordinates", 2)
    end
    for i = 1, n do
      local v = select(i, ...)
      if type(v) ~= "number" and type(v) ~= "table" then
        error("draw: argument " .. (i + 1) .. " should be a number or quad, got "
          .. tostring(v), 2)
      end
    end
  end
  graphics.setCanvas = function(c)
    if c ~= nil and type(c) ~= "table" then
      error("setCanvas: canvas stub expected", 2)
    end
  end
  graphics.clear = function(r, g, b)
    if r ~= nil then
      expect_numbers("clear", r, g, b)
    end
  end
  graphics.getDimensions = function() return 720, 480 end
  graphics.push = function() end
  graphics.pop = function() end
  graphics.translate = function(x, y) expect_numbers("translate", x, y) end
  graphics.scale = function(s) expect_numbers("scale", s) end
  graphics.setScissor = function() end
  graphics.setLineWidth = function(w) expect_numbers("setLineWidth", w) end

  -- Deterministic time for the game's randomseed call.
  env.os = setmetatable(
    { time = function() return 1725868800 end },
    { __index = os })

  -- Module loader: searches the project root like LÖVE's require path
  -- ("./?.lua;./?/init.lua") plus src/ and lib/ for dot-names.
  local cache = {}
  local SEARCH = { "%s.lua", "%s/init.lua", "src/%s.lua", "lib/%s.lua", "src/%s/init.lua" }
  function env.require(name)
    if cache[name] then return cache[name] end
    local path = name:gsub("%.", "/")
    local chunk, source
    for _, pattern in ipairs(SEARCH) do
      local file = pattern:format(path)
      local f = io.open(file, "rb")
      if f then
        source = f:read("*a")
        f:close()
        chunk, source = source, file
        break
      end
    end
    if not chunk then
      error("harness: module '" .. name .. "' not found", 2)
    end
    local mod_env = setmetatable({}, { __index = env })
    mod_env.require = env.require
    local fn = assert(loadstring(chunk, "@" .. source))
    setfenv(fn, mod_env)
    local mod = fn()
    cache[name] = mod or true
    return cache[name]
  end

  env.love = {
    keyboard = {
      isDown = function(key) return keys_down[key] and true or false end,
    },
    joystick = {
      getJoysticks = function() return {} end,
    },
    event = {
      quit = function() quit_flag[1] = true end,
    },
    graphics = graphics,
  }
  env.TWANG_TEST.record_lines = function(sink) line_sink = sink end

  return env
end

-- Boots the game headlessly (entry main.lua) under the stubs and returns
-- the sandbox env; the live game instance is at env.TWANG_TEST.game and
-- the driver-owned key map at env.TWANG_TEST.keys_down (tests that need
-- to simulate held/pressed input mutate it between steps).
--
-- The game ships a single level now (the room grid, a no-entity camera
-- sandbox), but most suites exercise a level full of entities. So the
-- harness boots a legacy map by default; pass a `map_file` to boot
-- another (`config.map_file` for the shipped level).
function Harness.boot(map_file)
  local keys_down, quit_flag = {}, { false }
  local env = Harness.new_env(keys_down, quit_flag)
  -- the game's skip_select path boots config.map_file, so pinning it is
  -- all it takes to choose the boot level (the suites that assert on the
  -- shipped level pass "maps/roomgrid.json"). Use the sandbox loader so
  -- this is the same config table the game will read.
  env.require("src.config").map_file = map_file or "maps/legacy/level1.json"
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  env.love.load()
  env.TWANG_TEST.keys_down = keys_down
  return env
end

-- Captures the camera's pre-step state so pure_follow can predict where
-- the camera lands after a step. Take the snapshot BEFORE stepping, then
-- hand it to camera_steady together with the POST-step player.
function Harness.cam_snapshot(cam, player)
  return {
    cx = cam.x, cy = cam.y,
    ptx = cam.ptx, pty = cam.pty,
    had_ptx = cam.ptx ~= nil, ride = player.ride,
  }
end

-- The camera's position after one step, computed independently of
-- src/camera.lua: a pure damped follow of the player's clamped target,
-- plus the moving-block feed-forward, and NOTHING else.
--
-- The frame never shakes, so a camera sitting anywhere other than this
-- value means something has re-introduced an offset into cam.x/cam.y.
function Harness.pure_follow(pre, player, world, config, dt)
  local vw, vh = config.view.width, config.view.height
  local lo_x, hi_x, lo_y, hi_y = world:clamp_rect()
  local tx = math.max(lo_x, math.min(hi_x, player.x + player.w/2 - vw/2))
  local ty = math.max(lo_y, math.min(hi_y, player.y + player.h/2 - vh/2))
  local ride_dx, ride_dy = 0, 0
  if pre.ride and pre.had_ptx then
    ride_dx, ride_dy = tx - pre.ptx, ty - pre.pty
  end
  local f = 1 - (1 - config.camera.follow) ^ dt
  return pre.cx + (tx - pre.cx) * f + ride_dx * (1 - f),
         pre.cy + (ty - pre.cy) * f + ride_dy * (1 - f)
end

-- True when `cam` sits exactly on the pure follow (see pure_follow) and
-- carries no leftover shake state.
function Harness.camera_steady(cam, pre, player, world, config, dt)
  if cam.shake_t ~= nil or cam.shake_s ~= nil or cam.shake_len ~= nil then
    return false
  end
  local ex, ey = Harness.pure_follow(pre, player, world, config, dt)
  return cam.x == ex and cam.y == ey
end

return Harness
