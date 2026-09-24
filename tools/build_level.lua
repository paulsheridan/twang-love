-- Level builder: a small DSL that emits Tiled JSON maps for twang.
-- Not part of the game; the authoring tool behind the 8-level ladder
-- (docs/gameplan.md). Run from the project root: luajit tools/build_level.lua
--
-- Terrain sits on one tile grid ("Ground") over a full backdrop layer
-- ("Background", the pink pebble the committed farmhouse uses). Entities
-- are plain 16x16 rectangle objects (top-left anchored) except spawns,
-- which are point objects (feet at the point) -- matching the loader's
-- anchor conventions (src/tiled.lua).

local json = require("lib.json")

-- tile vocabulary (spritesheet ids, all confirmed against maps/twang.tsx)
local T = {
  SURF     = 36,  -- orange grass top (solid)
  FILL     = 2,   -- dark underground fill (solid)
  BLOCK    = 4,   -- orange block (solid)
  TOWER    = 50,  -- orange wall with window band (solid)
  ROCK     = 9,   -- dark rock (solid)
  STICKY   = 40,  -- pink pebble rock (solid + sticky)
  PHASE    = 135, -- switch-flipped platform (solid + phase)
  SLIT     = 79,  -- arrow slit (solid + arrow_pass)
  BACKDROP = 26,  -- pink pebble backdrop (visual only on Background)
}

local Builder = {}
Builder.__index = Builder

local function gid(t) return t + 1 end

function Builder.new(w, h)
  local self = setmetatable({}, Builder)
  self.w, self.h = w, h
  self.grid = {}
  for _ = 1, w * h do self.grid[#self.grid + 1] = 0 end
  self.objects = {}
  self.nextid = 1
  return self
end

function Builder:set(x, y, t)
  if x < 0 or x >= self.w or y < 0 or y >= self.h then return end
  self.grid[y * self.w + x + 1] = gid(t)
end

-- Flat ground: orange grass surface at `row`, dark fill to the bottom.
function Builder:ground(x0, x1, row)
  for x = x0, x1 do
    self:set(x, row, T.SURF)
    for y = row + 1, self.h - 1 do self:set(x, y, T.FILL) end
  end
end

-- Raw terrain rect of one tile id.
function Builder:fill(x0, y0, x1, y1, t)
  for y = y0, y1 do
    for x = x0, x1 do self:set(x, y, t) end
  end
end

-- 1-tile-tall floating platform.
function Builder:platform(x0, x1, row, t)
  self:fill(x0, row, x1, row, t or T.SURF)
end

-- Carve to empty (a void pit).
function Builder:carve(x0, y0, x1, y1)
  for y = y0, y1 do
    for x = x0, x1 do self:set(x, y, 0) end
  end
end

-- ==== entities ====

-- Registers one object. Plain rects anchor at their top-left tile; point
-- objects put the entity's feet at the point (the loader's convention).
function Builder:obj(name, kind, col, row, opts)
  opts = opts or {}
  local o = {
    id = self.nextid,
    name = name,
    type = kind,
    rotation = 0,
    visible = true,
  }
  self.nextid = self.nextid + 1
  if opts.point then
    o.point = true
    o.width, o.height = 0, 0
    o.x = col * 16
    o.y = (row + 1) * 16   -- feet at the row's bottom edge
  else
    o.width, o.height = 16, 16
    o.x = col * 16
    o.y = row * 16
  end
  if opts.props and next(opts.props) then
    local props = {}
    for k, v in pairs(opts.props) do
      props[#props + 1] = {
        name = k,
        type = type(v) == "boolean" and "bool"
          or (type(v) == "number" and "int" or "string"),
        value = v,
      }
    end
    o.properties = props
  end
  self.objects[#self.objects + 1] = o
  return o
end

-- Grouped helpers: "key_01" style names assign the entity's puzzle group.
function Builder:spawn(col, feet_row)
  return self:obj("spawn", "Spawn", col, feet_row, { point = true })
end

function Builder:exit(col, row)
  return self:obj("exit", "Exit", col, row)
end

function Builder:checkpoint(col, row)
  return self:obj("checkpoint", "Checkpoint", col, row)
end

function Builder:key(name, col, row)
  return self:obj(name, "Key", col, row)
end

function Builder:lock(name, col, row)
  return self:obj(name, "Lock", col, row)
end

-- A door object owns its tile: the terrain under it must be carved open.
function Builder:door(name, col, row)
  return self:obj(name, "Door", col, row)
end

-- Switch: `tile` overrides the off-art (93 keeps the on-art a puff, not
-- the exit flag). `phase` = true makes its strikes flip the phase tiles.
function Builder:switch(name, col, row, opts)
  opts = opts or {}
  local props = {}
  if opts.phase then props.phase = true end
  props.spr = opts.tile or 93
  return self:obj(name, "Switch", col, row, { props = props })
end

function Builder:spring(name, col, row)
  return self:obj(name, "Spring", col, row)
end

function Builder:winch(col, row)
  return self:obj("winch", "Winch", col, row)
end

-- Enemies: patrol bounds default to config.enemies.roam_tiles.
function Builder:enemy(kind, col, row)
  local Kind = kind:sub(1, 1):upper() .. kind:sub(2)
  return self:obj(kind, Kind, col, row)
end

-- ==== output ====

-- Writes the map: terrain grid plus the object layer. Levels carry no
-- backdrop sprites: the sky shows through (config.world.sky).
function Builder:save(path)
  local layers = {}
  layers[#layers + 1] = {
    type = "tilelayer", name = "Ground", visible = true,
    width = self.w, height = self.h, x = 0, y = 0, opacity = 1,
    data = self.grid,
  }
  layers[#layers + 1] = {
    type = "objectgroup", name = "Objects", visible = true,
    draworder = "topdown", x = 0, y = 0, opacity = 1,
    objects = self.objects,
  }
  local map = {
    type = "map", version = "1.10", tiledversion = "1.11.0",
    orientation = "orthogonal", renderorder = "right-down",
    infinite = false, compressionlevel = -1,
    width = self.w, height = self.h,
    tilewidth = 16, tileheight = 16,
    nextlayerid = #layers + 1,
    nextobjectid = self.nextid,
    tilesets = { { firstgid = 1, source = "twang.tsx" } },
    layers = layers,
  }
  local f = io.open(path, "wb")
  f:write(json.encode(map) .. "\n")
  f:close()
  print(("built %s (%dx%d tiles, %d objects)")
    :format(path, self.w, self.h, #self.objects))
end

-- ==== the levels ====

-- 1 · meadow: walk, jump, bow; keys -> locks -> doors -> exit, no enemies.
local function meadow()
  local L = Builder.new(110, 20)
  L:ground(0, 109, 16)
  -- edge walls keep the meadow walkable (no accidental void falls)
  L:fill(0, 10, 0, 15, T.BLOCK)
  L:fill(109, 10, 109, 15, T.BLOCK)
  L:spawn(3, 15)
  -- pedestal + key (teach: jump)
  L:fill(23, 13, 23, 15, T.BLOCK)
  L:key("key_01", 23, 12)
  -- first pit (teach: gaps kill)
  L:carve(32, 0, 35, 19)
  L:ground(36, 53, 16)
  -- gate A: a 2-tall door in the wall; its key sits on the ground before it
  L:fill(44, 10, 44, 13, T.BLOCK)
  L:carve(44, 14, 44, 15)
  L:door("door_01", 44, 14)
  L:door("door_01", 44, 15)
  L:key("key_01", 39, 15)
  L:lock("lock_01", 42, 15)
  -- second pit
  L:carve(54, 0, 57, 19)
  L:ground(58, 109, 16)
  -- key pedestal 2: a 3-tall column; hop on top to grab the key
  L:fill(62, 13, 62, 15, T.BLOCK)
  L:key("key_02", 62, 12)
  -- gate B: 2-tall door, its lock on the ground before it
  L:fill(68, 10, 68, 13, T.BLOCK)
  L:carve(68, 14, 68, 15)
  L:door("door_02", 68, 14)
  L:door("door_02", 68, 15)
  L:lock("lock_02", 66, 15)
  -- the exit flag on the open ground
  L:exit(76, 15)
  -- playful platform hops past the exit
  L:platform(88, 90, 13)
  L:platform(93, 95, 11)
  L:save("maps/meadow.json")
end

-- 2 · battlements: archers + the first switch-shot gate + sticky bounce.
local function battlements()
  local L = Builder.new(100, 20)
  L:ground(0, 37, 16)
  L:fill(0, 10, 0, 15, T.BLOCK)      -- left edge wall
  L:spawn(3, 15)
  -- cover block (teach: break the archer's line of sight)
  L:fill(18, 14, 18, 15, T.BLOCK)
  -- archer 1: flat ground ahead (the safe first meet: it starts facing
  -- away and paces; the player picks the moment)
  L:enemy("archer", 34, 15)
  -- pit
  L:carve(38, 0, 41, 19)
  L:ground(42, 59, 16)
  -- switch mount with a sticky face (missed arrows bounce back) and the
  -- switch on top: a lofted arrow opens the gate
  L:fill(42, 13, 42, 15, T.STICKY)
  L:switch("switch_01", 42, 12)
  -- gate wall with a 2-tall door
  L:fill(46, 11, 46, 13, T.BLOCK)
  L:carve(46, 14, 46, 15)
  L:door("door_01", 46, 14)
  L:door("door_01", 46, 15)
  -- second pit
  L:carve(60, 0, 63, 19)
  L:ground(64, 99, 16)
  -- rising steps to the keep plateau
  L:fill(70, 15, 70, 19, T.BLOCK)    -- 1-tall step
  L:ground(71, 73, 14)
  L:fill(74, 13, 74, 15, T.BLOCK)    -- riser onto the plateau
  L:ground(75, 99, 12)
  -- archer 2 guards the plateau's approach
  L:enemy("archer", 82, 11)
  -- the exit flag, framed by the keep's right wall
  L:exit(92, 11)
  L:fill(97, 7, 99, 11, T.BLOCK)
  L:save("maps/battlements.json")
end

-- 3 · the crossing: one rope swing over a void; melee chasers patrol.
local function crossing()
  local L = Builder.new(120, 20)
  -- entry plateau (the swing's launch point)
  L:ground(0, 29, 8)
  L:fill(0, 2, 0, 7, T.BLOCK)        -- left edge wall
  L:spawn(3, 7)
  L:checkpoint(6, 7)
  L:enemy("melee", 24, 7)
  -- the chasm (x 30..35): a 2-wide rope anchor block hangs over it at
  -- row 4; shoot up-forward, swing, release onto the low far ledge
  L:carve(30, 0, 35, 19)
  L:fill(34, 4, 35, 4, T.ROCK)
  -- far ledge (a drop of 6 tiles from the plateau)
  L:ground(36, 119, 14)
  L:checkpoint(41, 13)
  L:enemy("melee", 53, 13)
  L:enemy("melee", 96, 13)
  L:exit(107, 13)
  L:fill(119, 8, 119, 13, T.BLOCK)   -- right edge wall
  L:save("maps/crossing.json")
end

-- 4 · springside: switch-struck spring vaults; a phase wall dissolves.
local function springside()
  local L = Builder.new(120, 30)
  L:ground(0, 37, 24)
  L:ground(38, 119, 19)                -- the keep plateau (5 above ground)
  L:fill(0, 18, 0, 23, T.BLOCK)        -- left edge wall
  L:spawn(3, 23)
  L:checkpoint(5, 23)
  -- spring intro: stand on the pad, shoot the switch on the mount, and
  -- the vault carries you onto the wall (too tall to jump)
  L:spring("spring_01", 10, 23)
  L:fill(7, 21, 7, 23, T.BLOCK)        -- switch mount column
  L:switch("switch_01", 7, 20)
  L:fill(12, 19, 13, 23, T.BLOCK)      -- the vault wall (5 tall)
  -- melee chaser mid-level
  L:enemy("melee", 28, 23)
  -- phase wall blocks the corridor; the phase switch dissolves it
  L:fill(24, 18, 24, 23, T.PHASE)
  L:fill(20, 21, 20, 23, T.BLOCK)      -- switch mount column
  L:switch("switch_02", 20, 20, { phase = true })
  -- the cliff vault: spring at the plateau's base, switch on a mount
  L:spring("spring_02", 36, 23)
  L:fill(32, 21, 32, 23, T.BLOCK)      -- switch mount column
  L:switch("switch_03", 32, 20)
  -- archer guards the plateau approach; a cover block gives shade
  L:fill(46, 16, 46, 18, T.BLOCK)
  L:enemy("archer", 50, 18)
  L:exit(56, 18)
  L:fill(118, 13, 119, 18, T.BLOCK)    -- right edge wall
  L:save("maps/springside.json")
end

-- 5 · arrowslit: laser snipers; arrow slits (they block sight, not
-- your arrows) are the counterplay -- snipe flat through them and let
-- the patrol walk into the line, or hop the low wall and fight.
local function arrowslit()
  local L = Builder.new(120, 20)
  L:ground(0, 119, 16)
  L:fill(0, 10, 0, 15, T.BLOCK)      -- left edge wall
  L:spawn(3, 15)
  L:checkpoint(5, 15)
  -- laser 1 in the open (the fair intro: read the telegraph, break LOS)
  L:fill(18, 14, 18, 15, T.BLOCK)    -- cover block
  L:enemy("laser", 24, 15)
  -- first pit
  L:carve(30, 0, 33, 19)
  L:ground(34, 119, 16)
  -- slit wall 1: a 2-tall wall whose bottom cell is an arrow slit -- the
  -- laser beyond can't see through it, your arrows fly through it
  L:fill(42, 14, 42, 14, T.BLOCK)
  L:fill(42, 15, 42, 15, T.SLIT)
  L:enemy("laser", 48, 15)
  -- second pit
  L:carve(58, 0, 61, 19)
  L:ground(62, 119, 16)
  L:checkpoint(64, 15)
  -- slit wall 2
  L:fill(76, 14, 76, 14, T.BLOCK)
  L:fill(76, 15, 76, 15, T.SLIT)
  L:enemy("laser", 82, 15)
  -- an archer guards the exit
  L:enemy("archer", 100, 15)
  L:exit(110, 15)
  L:fill(119, 10, 119, 15, T.BLOCK)  -- right edge wall
  L:save("maps/arrowslit.json")
end

-- 6 · winchyard: rope arrows into winches zip the player across the
-- voids (reeled through, thrown out the far side).
local function winchyard()
  local L = Builder.new(110, 20)
  L:ground(0, 11, 18)
  L:fill(0, 12, 0, 17, T.BLOCK)      -- left edge wall
  L:spawn(3, 17)
  L:checkpoint(5, 17)
  -- zip 1: the winch hangs over the void; shoot up at it from the ledge
  L:carve(12, 0, 17, 19)
  L:fill(15, 11, 15, 11, T.BLOCK)    -- the winch's mount
  L:winch(15, 12)
  L:ground(18, 35, 18)
  L:checkpoint(20, 17)
  L:enemy("melee", 30, 17)
  -- zip 2
  L:carve(36, 0, 41, 19)
  L:fill(39, 11, 39, 11, T.BLOCK)
  L:winch(39, 12)
  L:ground(42, 59, 18)
  L:checkpoint(44, 17)
  L:enemy("melee", 52, 17)
  -- zip 3, then the final stretch
  L:carve(60, 0, 65, 19)
  L:fill(63, 11, 63, 11, T.BLOCK)
  L:winch(63, 12)
  L:ground(66, 109, 18)
  L:checkpoint(68, 17)
  L:enemy("archer", 78, 17)
  L:enemy("melee", 88, 17)
  L:exit(102, 17)
  L:fill(109, 12, 109, 17, T.BLOCK)  -- right edge wall
  L:save("maps/winchyard.json")
end

-- 7 · the vault: multi-group keys/doors; a bomb ride reaches the
-- high shelf's key; a laser and an archer cover the ground.
local function vault()
  local L = Builder.new(120, 20)
  L:ground(0, 119, 16)
  L:fill(0, 10, 0, 15, T.BLOCK)
  L:spawn(3, 15)
  L:checkpoint(5, 15)
  -- gate 1: a walk-in key opens the first door
  L:key("key_01", 12, 15)
  L:lock("lock_01", 16, 15)
  L:fill(20, 10, 20, 13, T.BLOCK)
  L:carve(20, 14, 20, 15)
  L:door("door_01", 20, 14)
  L:door("door_01", 20, 15)
  -- a key floating six tiles up: stand under it, bomb your feet, and
  -- the launch carries you up through it (unjumpable at 4 tiles)
  L:key("key_02", 26, 11)
  -- the perch: an archer covers the shelf's ground
  L:fill(34, 13, 34, 15, T.BLOCK)
    L:enemy("archer", 34, 12)
  L:carve(40, 0, 43, 19)
  L:ground(44, 119, 16)
  L:checkpoint(46, 15)
  -- a laser covers the lock's ground
  L:enemy("laser", 52, 15)
  L:lock("lock_02", 62, 15)
  L:fill(66, 10, 66, 13, T.BLOCK)
  L:carve(66, 14, 66, 15)
  L:door("door_02", 66, 14)
  L:door("door_02", 66, 15)
  -- a melee crowd in the vault's depth
  L:enemy("melee", 74, 15)
  L:enemy("melee", 80, 15)
  L:checkpoint(70, 15)
  L:exit(106, 15)
  L:fill(119, 10, 119, 15, T.BLOCK)
  L:save("maps/vault.json")
end

-- 8 · the keep: rocketeers and bombers over open sky; every tool counts.
local function keep()
  local L = Builder.new(130, 20)
  L:ground(0, 129, 16)
  L:fill(0, 10, 0, 15, T.BLOCK)
  L:spawn(3, 15)
  L:checkpoint(5, 15)
  -- zone A: a rocketeer with open sky (shoot its hanging rocket down)
  L:enemy("rocketeer", 24, 15)
  -- zone B: the trench (a dug pit; bomber grenades bounce in it)
  L:carve(38, 0, 45, 19)
  L:ground(38, 45, 18)               -- the trench floor (2 below ground)
  L:enemy("melee", 41, 17)
  L:enemy("melee", 44, 17)
  -- zone C: a laser and an archer at the keep's gate
  L:ground(46, 129, 16)
  L:checkpoint(52, 15)
  L:enemy("laser", 60, 15)
  L:enemy("archer", 68, 15)
  -- zone D: the second rocketeer and a bomber before the throne
  L:enemy("rocketeer", 84, 15)
  L:enemy("bomber", 94, 15)
  L:checkpoint(78, 15)
  L:enemy("melee", 104, 15)
  L:exit(120, 15)
  L:fill(129, 10, 129, 15, T.BLOCK)
  L:save("maps/keep.json")
end

meadow()
battlements()
crossing()
springside()
arrowslit()
winchyard()
vault()
keep()
print("levels built: meadow, battlements, crossing, springside, "
  .. "arrowslit, winchyard, vault, keep")
