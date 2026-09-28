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
| `oneway`    | bool   | thin platform: standable from above, passable from below — bodies land on it, arrows/enemies/sight pass through (tile 64, the blue slat) |
| `phase`     | bool   | switch-flipped platform: every instance of a `phase` tile in the level toggles solid<->non-solid together on strikes of `phase`-flagged switches (see below) |
| `runnable`  | bool   | wall-run lane marker: a line of these tiles is traversed by the player's wall-run (see below). Runnable tiles block nothing (players, enemies, arrows) — don't place them where a floor is needed. |
| `kind`      | string | entity role, one of the kinds below (classifies tile objects placed on Object Layers) |
| `slope`     | string | slope collision shape: `/floor`, `\floor`, `\ceil` or `/ceil`. Slope tiles must NOT have the `solid` property; slope collision is handled by the game. |

### One-way platforms (`oneway`)

A tile flagged `oneway` (the blue thin platform, tile 64) is a
standable-from-above slat: a falling body whose feet cross the tile's
top edge lands on it (the swept fall span can't tunnel through — a
max-speed fall is 9px/step and the catch sweeps that whole span).
Everything else passes through: it is not `solid`, so bodies rising
from below (jump up through it), arrows, enemy sight and laser beams
all ignore it. You cannot drop back down through it. Standing on one is
ground in every gameplay sense (jump, coyote time, the spirit charge,
walk caps) — `gr` flows as usual.

### Springs (`spring`)

Springs are **landing pads**: the pad fires the instant the player
lands on it — extend + launch (`config.springs.launch_velocity`), no
switch involved. A switch strike does nothing to a spring now. The
hitbox is the pad band at the tile's bottom (`config.springs.
pad_height` = 8px, matching the collapsed tile-16 art); the extended
state plays the tile-32 art (`spring_ext`).

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

### Wall-run lanes (`runnable`)

A tile flagged `runnable` (the checkered box) marks a wall-run lane: a
maximal horizontal line of consecutive runnable tiles in one row, at
least two tiles long. The tiles themselves are pass-through — nothing
collides with them; they are pure markers.

- **Trigger**: the player's body centre enters one of the line's first
  two tiles from a pushed end — the outermost tile, or one in from it —
  while holding jump and pushing the stick toward the line (right at the
  left end, left at the right end). The run engages: the body is
  pinned into the band (easing onto the row's centre line over
  `config.wallrun.settle_steps`) and carried along it at
  `config.wallrun.speed`.
- **Mid-run**: releasing the pushed direction stops the player and drops
  them straight down. Rope/winch modes own the body instead — the trigger
  is blocked while either is active.
- **Far end**: reaching the last tile ends the run. With jump still held
  the player jumps off the end (a standard, holdable jump that keeps the
  run's momentum); without it they keep the momentum and begin to fall.
- Middle tiles never engage the run (the catch zone is the first two
  tiles from a pushed end), and a held jump is not
  required to sustain it — only the direction is. Tuning lives in
  `config.wallrun`.

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
  (id + 1). Give a switch the bool property `phase` to make it drive the
  level's phase tiles on every strike — switches without the flag never
  touch the blocks (springs were switch-driven once; they are landing pads
  now and no longer answer strikes).
- **`spring`** — spring pad: fires the instant the player LANDS on it
  (extend + launch skyward; see "Springs" above). No switch wiring.
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
- **`gun`** — a placed gun pickup (the one laser riflemen drop on death,
  also placeable directly): walking into one collects it as ONE
  explosive shot — the bow's next normal firing launches the gun itself,
  which detonates on any contact like the bomb arrow's blast.
- **`pusher` family** (`pusher`, `updraft`, `outdraft` Placements; the
  kind IS the variant, all sharing sprite tile 86) — the pusher device:
  a solid one-tile block you hop over. A player arrow striking it is
  consumed (a poof into the device, like the winch capture) and the
  device fires its variant's shove with a constant great-force impulse
  — the launcher puzzle element:
  - **`updraft`** — a column drag: everything overlapping the device's
    column or `config.pusher.up.side` tiles (2) to either side, between
    the device's top edge and `config.pusher.up.reach` (64px — 4 tiles)
    above it, launches straight up. Legacy `pusher`-kind objects behave
    as updrafts.
  - **`outdraft`** — a sector drain: everything within
    `config.pusher.out.radius` (4 tiles) of the device's centre whose
    radial lies inside the `config.pusher.out.cone` (45° half-angle)
    around straight up is shoved along that radial, up-and-away; anyone
    beside or below the device feels nothing.
- Repeatable: every strike fires it again. A bomb arrow striking it
  detonates its own blast and the device's push together (stacking).
  Enemy darts never trigger it (and the spirit arrow fires no
  projectile, so it cannot strike anything). Per-instance
  overrides (`push`, `shove_grace`; updraft `reach`, `side`; outdraft
  `cone`, `radius` object properties) beat the defaults.
- **`mover` family** (`mover`, `mover_trigger` Classes; sprite tile 17,
  the plain orange block) — the moving blocks: a solid block of 1..3
  tiles a way that travels back and forth along a tile-aligned line from
  its rest position, pausing the same moment at each end (30 steps, 1s).
  The line's DIRECTION is the required `dir` property (`up`, `down`,
  `left` or `right`) — explicit only, nothing about the block's shape
  implies it, so a block of any footprint can run any way; a missing or
  misspelled `dir` skips the mover with a warning. It runs for the
  required `distance` (tiles) property — a mover without either
  property is skipped with a warning. Bodies standing on the top face
  ride it; anything solid or any body in its path STALLS it (never a
  crush).
  - **`mover`** (auto) cycles forever: rest -> out -> pause -> back ->
    pause -> out again.
  - **`mover_trigger`** waits parked at rest until the player LANDS on
    its top face (a fresh landing: a rider who never gets off keeps it
    parked) or a player arrow tip enters any tile of the block (the
    arrow consumed, pusher-style; a bomb arrow detonates first, then
    fires it). It then runs to the far end, pauses, and returns on its
    own to park again.
  - Per-instance overrides: `speed` (px per world-time step, default
    `config.mover.speed` = 1.0 — INTEGER speeds scroll perfectly
    evenly; fractional ones stutter on the pixel canvas) and `pause`
    (steps at each end, default 30). The footprint: explicit
    `tiles_w`/`tiles_h` (int tiles) properties win; otherwise the
    object's own placed size (resize the mover object in Tiled) rounds
    to tiles. Both clamp to `config.mover.max_tiles` = 3 each way
    (minimum 1). Level1's debug sandbox carries the demo pair.

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

Worked example: `maps/rooms_demo.json` (the level select's "rooms demo"
row) — two side-by-side 480x320 rooms with a seam pit between them;
crossing it wipes the screen into room B.

### Authoring rooms in Tiled (step by step)

1. Open the level (16x16, the `twang.tsx` tileset).
2. **Layer menu → Add Object Layer** (name it e.g. `Rooms`).
3. Select the **Insert Rectangle** tool (`R`). Draw a rectangle:
   - its **top-left must sit on a tile corner** — turn on the 16px grid
     and snap (the loader warns and snaps otherwise),
   - size it a **multiple of the 480x320 view** (480 wide x 320 tall
     for one screen; 960x320 for a two-screen-wide room). A room
     smaller than the view instead centres the camera (a load warning
     notes it).
4. With the rectangle selected, set its **Class** (the `type` field in
   older Tiled) to `room`. Case-insensitive — `Room` works.
5. Optionally set the rectangle's **Name** (`room_a`, `lower_vault`…).
   Names are for you; the game only reads Class/kind and geometry.

Rules the loader enforces / warns about:

- Rooms snap to the tile grid at load; overlaps warn.
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

