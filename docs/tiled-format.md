# Tiled level format for twang

Levels are Tiled (mapeditor.org) JSON maps in `maps/`, loaded by
`src/tiled.lua`. Open them in Tiled as an **8x8 orthogonal map**.

## Tilesets: any number, either size

A map may reference **N tilesets** (`m.tilesets`), each with its own
image and its own geometry. Tiled dispatches a gid to whichever
tileset's `firstgid` range it falls in, so you can add, drop or
re-cut tilesets without touching the game.

| tile size | role | what it is for                                        |
|-----------|------|-------------------------------------------------------|
| 8x8       | **terrain** | paints the collision grid and carries the gameplay flags |
| 16x16     | **art** | characters, objects and numbers: placed as objects, or as tile objects, never as terrain |

Both of Tiled's tileset shapes work:

- a **sheet** — one `<image>`, tiles cut out of it by source rect
  (honouring `columns`, `margin` and `spacing`);
- a **collection** — every `<tile>` carries its own `<image>`, and
  there is no sheet at all. This is what Tiled produces for
  hand-painted terrain, and it is what `maps/roomgrid.json` uses.

An image `source` inside a `.tsx` is resolved **relative to that
`.tsx`**, so `"../sheet.png"` in `maps/foo.tsx` means
`spritesheet.png` at the project root. Both absolute and relative
paths work.

> **Properties live in the tileset, not the map.** Flagging a tile
> `solid`/`bounce`/etc. writes a `<properties>` block into the **tileset**
> file. When a map references an external `.tsx` (which every level here
> does), that is a *different file* from the map: saving the map does not
> save the tileset, and a level saved without it loads with unflagged
> tiles — everything is paint, so the player walks straight through the
> walls. If tiles you just marked are not solid, save the `.tsx` as well.
> The loader prints a note when a level paints terrain and *not one* of
> those tiles carries a property, so the mistake is never silent.

## Tile keys and the resolved tile table

A map's tile layer stores each cell as a **key**: four hex digits,
row-major. The key is the tile's **gid** — its index across every
tileset the map references — and it indexes `level.tiles_by_key`, a
flat table of records the loader builds while reading the map:

```lua
{ key = 527, id = 526, image = "spritesheet.png", columns = 32,
  sx = 112, sy = 128, w = 8, h = 8,
  terrain = true, solid = true, bounce = true, ... }
```

Because the record carries its own image, source rect, size and flags,
nothing downstream knows or cares which tileset a tile came from.
`World:tile_record(key)` looks one up; `World:flag(key, "solid")` reads
a property straight off it.

## Art by role name

16x16 art is resolved two ways, and the placed tile always wins:

1. **the placed tile** — if you drop a 16x16 tile as a tile object, the
   entity draws that exact cell;
2. **the role name** — otherwise the entity takes the art whose `kind`
   property matches its role, so you can restyle a whole level's
   interactables from the tileset without re-placing them.

`level.art` is the role table, gathered from every non-terrain tileset
in the map. `config.art_file` (`maps/chars.tsx`) is a **global**
character tileset, loaded once at boot, supplying the player animation
frames and the HUD icons. `Level.build` merges the level's own art
**over** the global art, so any level can override a role just by
declaring the same `kind` in one of its tilesets.

Player frames and HUD icons are named roles, not fixed cells:

| role                                   | used for                              |
|----------------------------------------|---------------------------------------|
| `player_idle`, `player_air`, `player_aim_down`, `player_land` | the standing / jumping / aiming-down / landing frames |
| `player_run_0`..`player_run_3`         | the run cycle (`player_run` is the fallback) |
| `player_wallrun_0`..`player_wallrun_3` | the wall-run cycle                    |
| `heart_full`, `heart_half`, `heart_empty` | the HUD heart slots                |

A 16x16 entity still occupies a **2x2 block of 8x8 terrain cells** for
its footprint (doors, springs, switches, pushers, movers). That is a
footprint convention, not a subdivision of its art: entity art is drawn
whole from its own 16x16 tileset and is never cut into quarters.

## Tile properties

| property    | type   | meaning                                                        |
|-------------|--------|----------------------------------------------------------------|
| `solid`     | bool   | blocks the player, enemies and arrows                          |
| `bounce`    | bool   | arrows reflect off these instead of embedding, and never stick (see `config.arrows.max_bounces`) |
| `friction`  | bool   | slippery ground (low friction, like pico-8 flag 2)             |
| `arrow_pass`| bool   | arrows (player and enemy) fly through, but it still blocks the player and enemies — arrow slits |
| `oneway`    | bool   | thin platform: standable from above, passable from below — bodies land on it, arrows/enemies/sight pass through |
| `phase`     | bool   | switch-flipped platform: every instance of a `phase` tile in the level toggles solid<->non-solid together on strikes of `phase`-flagged switches (see below) |
| `runnable`  | bool   | wall-run lane marker: a line of these tiles is traversed by the player's wall-run (see below). Runnable tiles block nothing (players, enemies, arrows) — don't place them where a floor is needed. |
| `kind`      | string | entity role, one of the kinds below (classifies tile objects placed on Object Layers) |

The game is driven entirely by these per-tile custom properties — no
flags are hardcoded in level data, and there is no built-in fallback
table of reserved cells. A role with no art anywhere simply draws
nothing.

### Bounce surfaces (`bounce`)

A tile flagged `bounce` is an arrow surface: an arrow that reaches it
reflects off, conserving its speed, and is never embedded in it — so it
can never become a wall perch, a rope anchor, or a key-carrying surface
to land on. After `config.arrows.max_bounces` reflections the next one
spins the arrow out and it vanishes (see `spin_out_frames`).

`bounce` is enough on its own to catch arrows, whether or not `solid` is
also set: the loader treats a bounce tile as solid *for arrows*, so
marking only `bounce` still gets the reflection rather than an arrow
sailing quietly through. What it does **not** do is stop bodies — add
`solid` as well for a wall the player and enemies are stopped by (a
bounce field the player can walk through but not shoot past). Pair it
with `friction` for ice-like slides, and remember the two flags are
independent: `solid` + no `bounce` embeds arrows (the ordinary wall).

The legacy `sticky` property is a second spelling of the same flag, kept
so the old `maps/legacy/twang.tsx` spritesheet tileset keeps working: a
tile flagged `sticky` reflects arrows exactly like one flagged `bounce`.
New levels should author `bounce`; the two never conflict (either one
wins, they set the same field). Bomb arrows and gun shots are unaffected
— they detonate on *any* contact, bounce surface or not.

There is no `slope` property: slope collision is not implemented. Ramps
and slopes have to be built out of ordinary solid tiles (which is what
`maps/roomgrid.json` does with its 178 ramp cells).

### One-way platforms (`oneway`)

A tile flagged `oneway` (the blue thin platform) is a
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
state plays the art-32 cell (`spring_ext`).

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

A tile flagged `runnable` (the checkered box, art 81) marks a wall-run
lane: a maximal horizontal band where BOTH 8px rows of a 16px art row
are runnable, at least two art tiles long. The tiles themselves are
pass-through — nothing collides with them; they are pure markers.

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
    16px block or `config.pusher.up.side` art tiles (2) to either side,
    between the device's top edge and `config.pusher.up.reach` (64px)
    above it, launches straight up. Legacy `pusher`-kind objects behave
    as updrafts.
  - **`outdraft`** — a sector drain: everything within
    `config.pusher.out.radius` (64px) of the device's centre whose
    radial lies inside the `config.pusher.out.cone` (45° half-angle)
    around straight up is shoved along that radial, up-and-away; anyone
    beside or below the device feels nothing.
- Repeatable: every strike fires it again. A bomb arrow striking it
  detonates its own blast and the device's push together (stacking).
  Enemy darts never trigger it (and the spirit arrow fires no
  projectile, so it cannot strike anything). Per-instance
  overrides (`push`, `shove_grace`; updraft `reach`, `side`; outdraft
  `cone`, `radius` object properties) beat the defaults.
- **`mover` family** (`mover`, `mover_trigger` Classes; sprite art 17,
  the plain orange block) — the moving blocks: a solid block of 1..3
  art tiles (16px cells) a way that travels back and forth along a
  tile-aligned line (8px map tiles) from its rest position, pausing the
  same moment at each end (30 steps, 1s).
  The line's DIRECTION is the required `dir` property (`up`, `down`,
  `left` or `right`) — explicit only, nothing about the block's shape
  implies it, so a block of any footprint can run any way; a missing or
  misspelled `dir` skips the mover with a warning. It runs for the
  required `distance` (8px map tiles) property — a mover without either
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
    `tiles_w`/`tiles_h` (int art tiles) properties win; otherwise the
    object's own placed size (resize the mover object in Tiled) rounds
    to art tiles. Both clamp to `config.mover.max_tiles` = 3 each way
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
- a door object OWNS its 16px art block (a 2x2 run of 8px cells): its
  state alone decides the block's solidity, so a 2-block-tall door can
  be authored as two door objects stacked over doorway art

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

Worked example: `maps/legacy/rooms_demo.json` (a legacy workshop map) —
two side-by-side 480x320 rooms with a seam pit between them; crossing it
wipes the screen into room B. `maps/roomgrid.json` (the shipped level,
the menu's only row) is the other worked example: 25 rooms laid out as a
5x5 grid of 480x320 cells (a 300x200 tile map), nothing but a spawn in
the bottom-left cell and an exit in the top-right one.

### Authoring rooms in Tiled (step by step)

1. Open the level (8x8; the room grid's terrain tileset is
   `maps/roomgrid.tsx`).
2. **Layer menu → Add Object Layer** (name it e.g. `Rooms`).
3. Select the **Insert Rectangle** tool (`R`). Draw a rectangle:
   - its **top-left must sit on a tile corner** — turn on the 8px grid
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

## No cart fallbacks

There is **no built-in fallback table**. Art and roles come from the
tilesets a map references, plus the global character tileset
(`config.art_file`) for the player and HUD. A role that no tileset
declares simply has no art and draws nothing — that is the intended
signal that the tileset is missing something, rather than a silent
substitute from a legacy sprite label.

## Legacy maps

The maps in `maps/legacy/` that were built against the old single-sheet
pipeline (`twang.tsx` over `spritesheet.png`, plus `chars16.tsx`) still
load under the current loader, and the test suite exercises them. They
are on the way out: nothing in the engine needs them, and a level is
free to reference a different set of tilesets entirely. The one thing
worth carrying over from a legacy map is its terrain — the room grid,
the 178 ramp cells and any hand-placed geometry — re-pointed at fresh
tilesets.

