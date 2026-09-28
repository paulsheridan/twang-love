-- Puzzle interactables: keys, locks, doors, switches and springs.
--
-- Grouping (see src/tiled.lua for how groups are assigned in Tiled):
--   * a lock opens every door of its group once ALL locks of that group
--     are triggered (nil groups match each other: ungrouped = one global
--     puzzle)
--   * a switch strike opens its group's doors while every switch of the
--     group is on, and closes them again otherwise
--   * springs are landing pads: no switch drives them (Player.physics
--     fires the pad on the landing edge; spring_vault does the launch)
--   * only switches flagged "phase" (a Tiled bool property) flip the
--     level's phase tiles (switch-flipped platforms) solid<->non-solid,
--     so a door switch never dissolves the blocks

local config = require("src.config")

local Interactables = {}

-- A carried key may trigger this lock? Grouped items only pair within
-- their group; anything ungrouped (nil) works with anything.
function Interactables.key_fits_lock(key, lock)
  return not key.g or not lock.g or key.g == lock.g
end

-- Triggers a lock; opens its group's door(s) once every lock of that
-- group is triggered. Used by key-carrying arrows and a key-carrying
-- player alike. Door tiles leave the map at scan; the list draws them.
function Interactables.trigger_lock(ents, lock)
  lock.triggered = true
  local all_triggered = true
  for _, other in ipairs(ents.locks) do
    if other.g == lock.g and not other.triggered then
      all_triggered = false
      break
    end
  end
  if all_triggered then
    for _, door in ipairs(ents.doors) do
      if not door.open and door.g == lock.g then
        door.open = true
      end
    end
  end
end

-- Springs are LANDING PADS now (no switches): the pad fires itself the
-- instant the player lands on it — see Player.physics. This helper does
-- the vault: the one standing on the pad surface is launched skyward.
-- `spring` may carry a group (unused now; kept so future wiring can
-- scope strikes), and `player` is the landing body.
function Interactables.spring_vault(ents, spring, body)
  local tw = config.tile_size
  local pad = config.springs.pad_height
  local stand = spring.y + tw - pad
  if body.gr and math.abs((body.y + body.h) - stand) <= 4
  and body.x + body.w > spring.x and body.x < spring.x + tw then
    body.vy = config.springs.launch_velocity
    body.gr = false
    body.j_frames = 0
    return true
  end
  return false
end

-- Steps spring extension art timers by `dt` steps of world time. Springs
-- are landing pads now (fired by the player's landing, src/player.lua):
-- this pass only ages the extended art.
function Interactables.update_springs(ents, dt, world)
  local tw = config.tile_size
  for _, spring in ipairs(ents.springs) do
    -- springs beyond the active room hold their extension (off-screen)
    if spring.ext and (not world
    or world:in_room(spring.x + tw/2, spring.y + tw/2)) then
      spring.ext = spring.ext - dt
      if spring.ext <= 0 then
        spring.ext = nil
      end
    end
  end
end

-- Test-menu puzzle disable: hides every key, lock and door. Keys and
-- locks reuse their existing "gone" flags (taken / triggered), doors are
-- forced open (they stop drawing and stop blocking) with a `disabled`
-- flag so switch strikes cannot re-close them while hidden. The prior
-- state is remembered per piece, so toggling back restores exactly what
-- was there before (consumed keys stay consumed). Carried keys — in the
-- player's hand or on an arrow — drop off silently (no poof).
function Interactables.set_puzzle_disabled(ents, player, disabled)
  if disabled then
    for _, k in ipairs(ents.keys) do
      k.taken = true
    end
    for _, l in ipairs(ents.locks) do
      l.triggered_prev = l.triggered or false
      l.triggered = true
    end
    for _, d in ipairs(ents.doors) do
      d.open_prev = d.open or false
      d.open = true
      d.disabled = true
    end
  else
    for _, k in ipairs(ents.keys) do
      -- keys only rest at "taken" when consumed (used) or when they
      -- were carried at disable time — carried ones were detached, so
      -- every unconsumed key returns to the world
      k.taken = (k.used and true) or false
    end
    for _, l in ipairs(ents.locks) do
      l.triggered = l.triggered_prev or false
      l.triggered_prev = nil
    end
    for _, d in ipairs(ents.doors) do
      d.open = d.open_prev or false
      d.open_prev = nil
      d.disabled = nil
    end
  end
  -- carried keys vanish along with everything else (a re-enabled key
  -- reappears in the world, not in hand)
  if player then player.key = nil end
  for _, a in ipairs(ents.arrows) do a.key = nil end
end

-- Switch groups drive their doors dynamically: every switch in the
-- group on -> the group's doors open; any off -> they close again.
-- Doors hidden by the test menu are skipped so a strike cannot re-close
-- them while the puzzle is disabled.
function Interactables.eval_switch_doors(ents, group)
  local all_on = true
  for _, switch in ipairs(ents.switches) do
    if switch.g == group and not switch.on then
      all_on = false
      break
    end
  end
  for _, door in ipairs(ents.doors) do
    if door.g == group and not door.disabled then door.open = all_on end
  end
end

-- Flips the level's phase tiles (all instances of the tileset's "phase"
-- tile) solid<->non-solid together. Called only for strikes of switches
-- flagged "phase" — other switches never touch the blocks.
function Interactables.toggle_phase_tiles(world)
  world.phase_solid = not world.phase_solid
end

return Interactables
