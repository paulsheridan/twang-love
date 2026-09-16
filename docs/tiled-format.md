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

## Entities on Object Layers

Entities (spawn/key/lock/door/archer/melee/switch/spring) live as tile
objects on Object Layers in Tiled (e.g. `items` and `entities`).

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

## Cart fallbacks

If the tileset defines no kind/slope properties at all, the pico-8 cart
defaults in `src/tiled.lua` apply, so a migrated level needs no manual
setup. The per-kind tile ids used for sprite fallbacks are in
`src/config.lua` (`config.tiles`).
