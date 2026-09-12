-- twang: archer side-scroller
-- love2d port of twang.p8
--
-- Thin bootstrap: forwards LÖVE callbacks to src/game.lua, the game
-- orchestrator. Tuning lives in src/config.lua; see README.md for controls
-- and docs/architecture.md for how the code is laid out.

local Game = require("src.game")

local game

function love.load()
  game = Game.new()
  game:load()
  -- test hook: expose the live game to the headless harness
  if TWANG_TEST then
    TWANG_TEST.game = game
  end
end

function love.update(dt)
  game:update(dt)
end

function love.draw()
  game:draw()
end

function love.keypressed(key, sc, isrepeat)
  game:keypressed(key, isrepeat)
end

function love.focus(focused)
  game:focus(focused)
end

function love.gamepadpressed(pad, button)
  game:gamepadpressed(button)
end

-- test hook (test-only snapshot; inert in a real LÖVE run)
if TWANG_TEST then
  TWANG_TEST.trace = function(step)
    return game:snapshot(step)
  end
end
