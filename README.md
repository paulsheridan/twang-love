# twang

An archer side-scroller: a LÖVE 11 port of the twang pico-8 cart. Native
240x160 pixel rendering, a 30hz fixed-timestep simulation and a smooth
camera. Levels are edited in Tiled (see `docs/tiled-format.md`).

## Running

Requires [LÖVE 11](https://love2d.org). From this directory:

```sh
love .
```

## Controls

| action | keyboard | gamepad |
|--------|----------|---------|
| move   | arrow keys | dpad / left stick |
| jump   | x | A / B |
| bow (hold to aim) | z | right bumper / right trigger |
| aim angle (while aiming) | left/right | left stick (analog) |
| power (while aiming) | up/down | physical dpad up/down |
| swap arrow type | c | X |
| fullscreen | f11 | — |
| controls panel | m / tab | start |
| quit | escape | back |

While aiming, the world runs in slow motion and the bow's trajectory is
previewed. Power levels: `lo` / `md` / `hi`.

The window opens at 6x the native 240x160 view (1440x960) and is
resizable; fullscreen (F11) keeps your desktop resolution. The game
always blits at a whole-number scale, so pixels stay square and sharp —
in fullscreen the image is centred and letterboxed rather than
stretched. The window also re-fits itself automatically when dragged to
a monitor with a different resolution, so it stays crisp everywhere.

## Gameplay

- Walk, jump (coyote time + jump buffering), and shoot arrows.
- Arrows stick into walls, bounce off sticky surfaces, and can be stood
  on when embedded in vertical walls.
- **Rope arrows** (press `c` to swap): limited-range arrows that anchor a
  rope between you and wherever they stick. Swing pendulum-style — your
  speed carries into and out of the swing, left/right pumps it, and
  up/down reels the rope in/out. Press jump to let go and keep your
  momentum. Miss the wall and the arrow poofs at max range.
- Carry keys to locks (personally, or by shooting them from an arrow)
  to open doors. Switches open/close doors while latched and trigger
  spring vaults; spring switches pop back out once the spring resets,
  ready to be shot again.
- **Archers hunt**: they spot you only in front of them, with clear line
  of sight and within range. Once spotted they draw briefly (you'll see
  their ballistic arc, like your own) and release a volley of three
  arrows one after another. While you stay visible they keep firing on
  a quick, randomized cadence; the moment they lose you they fire
  anyway (if mid-draw) and come looking for where you were — even off
  their platform, though they refuse drops deeper than four tiles.
  Archers wedged against a wall on a small perch hold the edge instead
  of pacing.
- Melee enemies hurt on touch. Arrow tips kill.
- You have three hearts (drawn top-left): a melee touch or enemy arrow
  costs half a heart, with a brief invulnerability blink after each hit.
  Heart slots show full, half-drained and empty sprites. Losing the last
  half-heart respawns you (dropping any unconsumed key). Falling off the
  world kills outright.
- Enemies patrol at most ~10 tiles from where they were placed in Tiled
  (see `config.enemies.roam_tiles`).
- Fall off the world and you respawn (dropping any unconsumed key).

## Code

See `docs/architecture.md` for the module map, data flow and the
simulation's quirks. All tuning constants live in `src/config.lua`.

## Tests

A snapshot harness keeps the simulation honest, and a behaviour suite
covers the enemy AI:

```sh
luajit tests/run.lua main.lua /tmp/trace.txt
luajit tests/trace_diff.lua tests/trace_baseline.txt /tmp/trace.txt
luajit tests/enemies_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
luajit tests/interactables_test.lua
```

The trace diff must be empty. After an *intentional* gameplay change,
rebase the baseline first (see docs/architecture.md). Requires LuaJIT
(headless; no LÖVE needed).

## Tools

- `tools/p8_to_tiled.lua` — migrates the original pico-8 cart to a Tiled
  JSON map: `luajit tools/p8_to_tiled.lua ../twang.p8 maps/level1.json`
- `tools/import_kenney.py` — spritesheet asset import

## Repository

The original pico-8 cart lives one directory up (`../twang.p8`).
