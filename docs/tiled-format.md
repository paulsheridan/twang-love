# Tiled level format for twang

Levels are Tiled (mapeditor.org) JSON maps in `maps/`, loaded by
`src/tiled.lua`. Open them in Tiled as a **16x16 orthogonal map** with
the `twang.tsx` tileset (16 columns, firstgid 1; the 256x256 sheet whose
tiles are 2x2 upscales of the cart's 8x8 art). External tilesets are
resolved from `.tsx` files next to the map.

The game is driven entirely by per-tile custom properties set on the
tileset — no flags are hardcoded in level data.

## Tile properties

| property    | type   | meaning                                                        |
|-------------|--------|----------------------------------------------------------------|
| `solid`     | bool   | blocks the player, enemies and arrows                          |
| `sticky`    | bool   | arrows bounce off these (see `config.arrows.max_bounces`)      |
| `friction`  | bool   | slippery ground (low friction, like pico-8 flag 2)             |
| `arrow_pass`| bool   | arrows (player and enemy) fly through, but it still blocks the player and enemies — arrow slits |
| `phase`     | bool   | switch-flipped platform: every instance of a `phase` tile in the level toggles solid<->non-solid together on strikes of `phase`-flagged switches (see below) |
| `kind`      | string | entity role, one of the kinds below (classifies tile objects placed on Object Layers) |
| `slope`     | string | slope collision shape: `/floor`, `\floor`, `\ceil` or `/ceil`. Slope tiles must NOT have the `solid` property; slope collision is handled by the game. |

### Phase tiles

A tile flagged `phase` (plus `solid`) is a platform controlled by
switches. There is one designated phase tile per level and no wiring on
the tile itself: only switches carrying the bool `phase` property flip
the global phase state on each strike, so all placed instances of that
tile become non-solid (or solid again) together — spring and door
switches never touch the blocks. Non-solid phase tiles block nothing
(players, enemies, player and enemy arrows) and are drawn translucent
(`config.phase.alpha`). Phase tiles start solid on level load; only
arrow strikes flip them (a spring switch popping back does not).

### `kind` values

- **`spawn`** — player spawn point
- **`key`** — key pickup (carried by arrows/player)
- **`lock`** — lock trigger (opens its group's door(s))
- **`door`** — door (solid until its group's locks fire)
- **`archer`** — archer enemy
- **`melee`** — melee enemy
- **`laser`** — laser rifleman enemy: hunts like an archer but fires a
  wall-to-wall laser beam (a full heart of damage) after a blinking
  sight telegraph; tuning lives in `config.enemies.laser_*`
- **`rocketeer`** — rocketeer enemy: hunts like an archer but lobs a
  homing rocket straight up (a full heart of blast damage, enemies in
  the blast die too); a player arrow tip detonates the rocket in
  flight; tuning lives in `config.enemies.rocket_*`
- **`switch`** — struck by arrows (no key needed); each strike toggles it and
  re-evaluates its group: all switches on -> the group's doors open, any
  off -> they close. The off art is the kind tile, the on art the next tile
  (id + 1). Switches also extend their group's springs when a strike turns
  them on. Give a switch the bool property `phase` to make it drive the
  level's phase tiles on every strike — switches without the flag never
  touch the blocks (spring/door switches and phase switches stay
  independent)
- **`spring`** — spring pad: a switch strike in its group extends it for a
  moment and vaults whoever stands on it into the air
- **`spring_ext`** — the extended spring art (not placed)
- **`winch`** — motorized rope reel: a rope arrow that strikes it is
  consumed and the player is reeled straight into the winch's centre at
  an accelerating speed (unstoppable; jump does nothing mid-reel).
  Inside `config.winch.pass_radius` of the centre the reel cuts the
  line and the built-up momentum throws the player through the centre
  and out the opposite side (at least `config.winch.min_throw_speed`).
  Firing any arrow cancels a reel. Non-rope arrows fly straight through.
- **`exit`** — the level's exit flag: touching it clears the level
  (the run's time, deaths and grade go to the results panel, and the
  best time/grade are saved for the level select). Multiple exits
  allowed; the first touch wins.
- **`checkpoint`** — a green checkpoint flag: touching it makes it the
  death respawn point (a small poof marks the handover). Without a
  touched flag, deaths respawn at a spawn point (the legacy behaviour).

## Entities on Object Layers

Entities (spawn/key/lock/door/archer/melee/laser/rocketeer/switch/
spring/winch/exit/checkpoint) live as tile objects on Object Layers in
Tiled (e.g. `items` and `entities`).

The object's role comes from, in order:

1. a `kind` custom property on the object
2. the placed tile's `kind` property on the tileset
3. the object's Class field (case-insensitive: `Door` -> `door`)

A key/lock/door object's puzzle group comes from, in order:

1. a `group` custom property
2. the object's name, with a leading `<kind>_` prefix stripped
   (`key_01`, `lock_01` and `door_01` share group `01`)
3. the object's name as-is (`front_door` -> group `front_door`)

Grouping rules:

- a grouped key only triggers grouped locks of the same group;
  ungrouped keys/locks work with anything
- a door opens once every lock in its group is triggered (ungrouped
  locks for an ungrouped door) and opens every door of that group
- a door object OWNS its tile: its state alone decides the tile's
  solidity, so a 2-block-tall door can be authored as two door objects
  stacked over doorway art

Any other custom property on an object is passed through to the game
entity and overrides that entity's defaults (per-instance tuning, e.g.
shoot cooldowns).

## Tile layers

Tiles in tile layers are terrain/decoration only: no entity tiles are
scanned from tile layers except the legacy `spawn` marker (see
`src/level.lua`). Tiles without properties are drawn as-is. Any number of
visible tile layers is allowed; later layers overwrite earlier ones where
they place a nonzero tile (higher layer wins, like Tiled's draw order).

Layer names give two of them a special, purely visual role
(case-insensitive):

- **`background`** — backdrop scenery. Parsed and kept per level but
  **never rendered** any more: levels carry no backdrop sprites, and
  the void behind everything is the flat sky blue of
  `config.world.sky`. (The layer's data survives in the map so Tiled
  authors keep their backdrop work; the game just doesn't draw it.)
- **`foreground`** — overlay scenery (buildings, hidden spaces), drawn on
  top of everything, the player included. It never collides either.
  Whenever the player walks behind any of it, the whole layer fades out
  smoothly (`config.foreground`) so their avatar stays visible, and
  fades back in once they step out.

Every other visible tile layer is gameplay terrain: merged into one
collision/draw grid, later layers winning on nonzero tiles.

## Rooms

A level can be split into **rooms** — camera-framed regions that gate
what the camera shows and what simulates. Rooms are **plain rectangle
objects** (no tile) on any Object Layer with the Class/kind `room`
(case-insensitive), optionally named for debugging. The map stays one
contiguous world: terrain, entities and puzzle state are shared across
rooms and persist.

- Rooms snap to the tile grid at load; overlaps warn.
- Rooms should be at least one view (480x320) — smaller ones centre the
  camera in the room instead of scrolling (a load warning notes it).
- Rooms need not cover the whole map: uncovered "wilderness" clamps the
  camera to the whole map and simulates everything (a warning notes it).
- A map with no `room` objects behaves exactly as before (one implicit
  room, the whole map).

At runtime:

- **Camera** — clamped to the active room's bounds (the room containing
  the player's centre).
- **Transitions** — crossing into another room (hysteresis-checked,
  `config.rooms.hysteresis_px`) wipes the screen (`config.rooms.fade_steps`):
  fade out, the room switches with the camera snapped to the player at
  full black, fade in.
- **Simulation** — only entities inside the active room simulate
  (enemies, arrows, rockets, bombs, particles, spring timers). Off-room
  entities freeze mid-state and resume on re-entry. The player and
  player-facing systems always run.
- **Foreground** — the overlay fade is per room: walking behind any
  overlay tile of the active room fades that room's foreground; other
  rooms keep theirs. The fade holds during a wipe.
- **Spawns/respawns** resolve the room from the spawn point (camera
  snaps, no wipe).

## Cart fallbacks

If the tileset defines no kind/slope properties at all, the pico-8 cart
defaults in `src/tiled.lua` apply, so a migrated level needs no manual
setup. The per-kind tile ids used for sprite fallbacks are in
`src/config.lua` (`config.tiles`).
