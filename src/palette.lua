-- The PICO-8 palette: 16 colours indexed 0 through 15.

local Palette = {}

Palette.COLOURS = {
  [0]  = {   0,   0,   0 },
  [1]  = {  29,  43,  83 },
  [2]  = { 126,  37,  83 },
  [3]  = {   0, 135,  81 },
  [4]  = { 171,  82,  54 },
  [5]  = {  95,  87,  79 },
  [6]  = { 194, 195, 199 },
  [7]  = { 255, 241, 232 },
  [8]  = { 255,   0,  77 },
  [9]  = { 255, 163,   0 },
  [10] = { 255, 236,  39 },
  [11] = {   0, 228,  54 },
  [12] = {  41, 173, 255 },
  [13] = { 131, 118, 156 },
  [14] = { 255, 119, 168 },
  [15] = { 255, 204, 170 },
}

--- Returns palette entry `index` as 0-1 normalised RGBA components,
--- falling back to black for unknown indices.
function Palette.rgb(index)
  local colour = Palette.COLOURS[index] or Palette.COLOURS[0]
  return colour[1] / 255, colour[2] / 255, colour[3] / 255, 1
end

return Palette
