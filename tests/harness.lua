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

  return env
end

-- Boots the game headlessly (entry main.lua) under the stubs and returns
-- the sandbox env; the live game instance is at env.TWANG_TEST.game and
-- the driver-owned key map at env.TWANG_TEST.keys_down (tests that need
-- to simulate held/pressed input mutate it between steps).
function Harness.boot()
  local keys_down, quit_flag = {}, { false }
  local env = Harness.new_env(keys_down, quit_flag)
  local chunk = assert(loadfile("main.lua"))
  setfenv(chunk, env)
  chunk()
  env.love.load()
  env.TWANG_TEST.keys_down = keys_down
  return env
end

return Harness
