-- Puzzle interactables: keys, locks, doors, switches and springs.
--
-- Grouping (see src/tiled.lua for how groups are assigned in Tiled):
--   * a lock opens every door of its group once ALL locks of that group
--     are triggered (nil groups match each other: ungrouped = one global
--     puzzle)
--   * a switch strike opens its group's doors while every switch of the
--     group is on, and closes them again otherwise
--   * a switch strike also extends every spring in its group, vaulting
--     whoever is standing on one

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

-- A switch strike extends every spring in its group for a moment and
-- vaults whoever is standing on one at that instant.
function Interactables.trigger_springs(ents, player, group)
  local tw = config.tile_size
  local pad = config.springs.pad_height
  for _, spring in ipairs(ents.springs) do
    if spring.g == group then
      spring.ext = config.springs.extension_frames
      -- vault the player standing on the pad (feet on its surface)
      local stand = spring.y + tw - pad
      if player.gr and math.abs((player.y + player.h) - stand) <= 2
      and player.x + player.w > spring.x and player.x < spring.x + tw then
        player.vy = config.springs.launch_velocity
        player.gr = false
        player.j_frames = 0
      end
      -- and any enemy standing on it
      for _, e in ipairs(ents.enemies) do
        if e.gr and math.abs((e.y + e.h) - stand) <= 2
        and e.x + e.w > spring.x and e.x < spring.x + tw then
          e.vy = config.springs.launch_velocity
          e.gr = false
        end
      end
    end
  end
end

-- Steps spring extension art timers. Switches that drive springs are
-- momentary: once every spring of the group has reset, the struck switch
-- pops back out so it can be shot again (door-driving switches stay
-- latched; they belong to groups without springs).
function Interactables.update_springs(ents)
  for _, spring in ipairs(ents.springs) do
    if spring.ext then
      spring.ext = spring.ext - 1
      if spring.ext <= 0 then
        spring.ext = nil
        local still_ext = false
        for _, other in ipairs(ents.springs) do
          if other.g == spring.g and other.ext then
            still_ext = true
            break
          end
        end
        if not still_ext then
          local popped = false
          for _, switch in ipairs(ents.switches) do
            if switch.g == spring.g and switch.on then
              switch.on = false
              popped = true
            end
          end
          if popped then Interactables.eval_switch_doors(ents, spring.g) end
        end
      end
    end
  end
end

-- Switch groups drive their doors dynamically: every switch in the
-- group on -> the group's doors open; any off -> they close again.
function Interactables.eval_switch_doors(ents, group)
  local all_on = true
  for _, switch in ipairs(ents.switches) do
    if switch.g == group and not switch.on then
      all_on = false
      break
    end
  end
  for _, door in ipairs(ents.doors) do
    if door.g == group then door.open = all_on end
  end
end

return Interactables
