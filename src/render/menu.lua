-- Controls panel overlay, drawn on the 240x160 canvas (pixelated).

local Palette = require("src.palette")

local pcol = Palette.rgb

return function()
  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 30, 34, 180, 74)
  love.graphics.setColor(pcol(6))
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", 30.5, 34.5, 179, 73)

  love.graphics.setColor(pcol(10))
  love.graphics.print("controls", 98, 40)

  love.graphics.setColor(pcol(7))
  love.graphics.print("stick/dpad/arrows: move", 52, 56)
  love.graphics.print("hold aim + stick: aim the bow", 52, 64)
  love.graphics.print("power: ud / dpad ud", 52, 72)
  love.graphics.print("jump: x / A / B     aim: z / RB / RT", 52, 80)

  love.graphics.setColor(pcol(12))
  love.graphics.print("m / start: panel      x: back", 52, 94)
  love.graphics.setColor(1, 1, 1, 1)
end
