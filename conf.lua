-- twang: archer side-scroller.
--
-- Window setup is driven by src/config.lua; see README.md for controls and
-- docs/architecture.md for how the code is laid out.

local config = require("src.config")

function love.conf(t)
  t.window.width  = config.view.width * config.window.scale
  t.window.height = config.view.height * config.window.scale
  t.window.title  = config.window.title
  t.window.vsync  = config.window.vsync
  t.window.resizable = true
  t.window.fullscreen = config.window.fullscreen
  t.window.fullscreentype = "desktop"  -- keep the desktop resolution
  t.window.highdpi = config.window.highdpi
  t.identity      = config.window.identity
end
