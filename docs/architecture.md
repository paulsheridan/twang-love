# twang architecture

A LÖVE 11 port of the twang pico-8 cart: a 240x160 native render at a
30hz fixed-timestep simulation with a smooth camera. Levels are Tiled
JSON maps (format documented in `docs/tiled-format.md`).

## Layout

```
main.lua                 thin bootstrap: forwards LÖVE callbacks to the game
conf.lua                 window setup, driven by src/config.lua
src/
  config.lua             every gameplay/rendering constant, in one place
  game.lua               orchestrator: owns state, runs the 30hz sim, renders
  input.lua              input state with pico-8 button semantics (btn/btnp)
  world.lua              tile grid, tile flags, solidity queries, slope collision
  level.lua              level assembly: scans Tiled objects into entity lists
  player.lua             player physics, bow aiming/firing, key carrying,
                         rope pendulum (attach/detach/winch)
   arrows.lua             player + enemy arrows (flight, bounce, stick, hits);
                          rope arrows (range, anchoring); also exposes
                          simulate_path (shared trajectory solver)
  enemies.lua            melee patrol; archers with a sense -> aim -> volley ->
                         investigate brain; patrols bounded by roam_tiles
  interactables.lua      key/lock/door/switch/spring puzzle logic
  particles.lua          poofs and blood
  camera.lua             smooth follow, clamped to the world
  sprites.lua            spritesheet quads + draw helper (flip/rot)
  palette.lua            the 16-colour pico-8 palette
  util.lua               small math/geometry helpers
  tiled.lua              Tiled JSON/TSX loader
  render/
    blit.lua             native canvas + window blit + HUD/menu composition
    world.lua            map, interactables, particles, enemies, arrows
    player.lua           player sprite + aim trajectory preview
    hud.lua              power indicator + control hints (window scale)
    menu.lua             controls panel overlay
lib/
  json.lua               vendored third-party JSON encoder/decoder
tests/
  harness.lua            headless LÖVE stubs (keyboard/gamepad/graphics)
  run.lua                scripted 900-step headless run, dumps state traces
  trace_diff.lua         diffs two traces (the refactor regression gate)
  legacy_main.lua        FROZEN copy of the pre-refactor monolith; the
                         reference oracle the refactor was verified against
tools/
  p8_to_tiled.lua        one-shot cart -> Tiled JSON migration
  import_kenney.py       spritesheet asset import
```

## Data flow

`game.lua` builds a single shared **context** (`ctx`) at load:

```
ctx = { config, input, world, ents, tiles, cam, player, die }
```

- `world` — the tile grid + flags + slope shapes (from `src/world.lua`),
  created from the loaded Tiled map and the interactable entity lists
- `ents` — live entity lists from `src/level.lua`: spawn_points, arrows,
  e_arrows, enemies, particles, keys, locks, doors, switches, springs
- `player` — the player body
- `die` — routes player deaths to `Player.die`; `hurt` routes damage to
  `Player.hurt` (systems never require `src/player.lua` for those;
  they call `ctx.die(ctx)` / `ctx.hurt(ctx)`)

Each sim step (`Game:step`, 1/30s) runs:

1. `input:step()` — press edges for this step
2. `Player.aim_step` — bow aiming, power levels, firing on release
3. full physics while **not** aiming (aim mode runs full physics only
   every `config.aiming.slow_motion_steps` steps — the bow slow-motion):
   player physics, player arrows, enemies, enemy arrows, particles,
   spring timers, camera

Rendering is a pure read of the same state: `render/blit.lua` draws the
world into the 240x160 canvas (world pass, then the player on top, then
the controls-panel overlay), blits it to the window preserving aspect,
and anchors the HUD to the blit rect. The blit scale is always a whole
number (letterboxing the remainder, fullscreen included), so game
pixels stay square and sharp at any window size; F11 toggles desktop
fullscreen. The window opens at `config.window.scale` (6x) and is
resizable — the blit re-fits every frame.

## Dependency rules

- `main -> game -> systems -> world/util/palette/config`
- systems never require each other sideways (except through the util
  layer); shared state lives in `ctx`, passed explicitly
- `render/*` modules only read state; nothing in a draw function mutates
  the game

## Simulation quirks worth knowing

- **Fixed timestep with accumulator.** dt is clamped
  (`config.sim.max_accumulator`) so tab-through never produces a huge
  catchup.
- **Everything draws on whole pixels.** Bodies move at fractional
  speeds; all sprite/line/point draw positions are floored, so nothing
  rasterizes unevenly on the pixel canvas (no shimmering edges).
- **The window fits its monitor.** `Game:fit_window` re-fits the window
  to an integer multiple of the 240x160 view whenever it lands on a
  different display (monitors differ in resolution and DPI scale, which
  otherwise leaves an oversized window for the WM to clamp — blurry,
  letterboxed). The blit always scales by a whole number.
- **Sub-frame input taps are never lost.** Held state is polled once per
  rendered frame, but press edges are evaluated once per sim step;
  key/gamepad press events additionally latch so a tap shorter than one
  rendered frame still fires. `btnp` repeats pico-8 style (every 4 steps
  after 15 held).
- **Mid-loop resets.** Player death clears the arrow lists; the arrow
  update loops read the list fresh each iteration and bail out when it
  is reset mid-loop. Player respawn reuses the same player table.
- **Jump corner forgiveness.** When a rising body clips a ledge with
  exactly one head corner, `resolve_y` slides it horizontally around
  the corner (up to `player.corner_nudge_px`, destination head corners
  verified free) instead of snapping below the tile and zeroing the
  velocity — jumps taken under ledges reach their full height. Both
  corners covered (a real overhang) or a blocked/over-cap slide falls
  back to the normal head bump. Inert for enemies, which never move
  upward.
- **Doors and springs own tiles.** A door's state alone decides its
  tile's solidity; springs are standable pads solid across the bottom
  `springs.pad_height` px of their tile (matching the inactive sprite's
  pad, so bodies stand on it instead of hovering), with `resolve_y`
  landing bodies on the pad surface; switch tiles are recessed (arrows
  fly in, bodies don't). Switches that drive springs are momentary —
  they pop back to inactive when every spring of their group has reset,
  so they can be shot again; every strike flips a switch on<->off.
- **Phase tiles flip with switch strikes.** Tiles flagged `phase` on the
  tileset (one designated tile per level, e.g. the platform ring, tile
  135) all toggle solid<->non-solid together on any switch strike,
  regardless of the switch's group; while non-solid they collide with
  nothing (bodies, arrows) and render translucent (`phase.alpha`).
  `World.phase_solid` is the single state flag, checked in
  `solid_at` and the map draw; spring pop-backs don't flip it — only
  arrow strikes do.
- **The archer brain** (below) runs archers; melee enemies just patrol.
- **Patrols are bounded.** Every enemy patrols at most
  `enemies.roam_tiles` (10) tiles from its spawn anchor (`home_x`,
  snapped at scan time) — on long flat ground it turns around at the
  roam limit instead of drifting away. Investigate walks are deliberate
  and exempt from the limit.
- **Hearts and i-frames.** The player's health is `player.hearts` (3)
  whole hearts tracked in half-hearts (`p.hp`, max 6); a melee touch or
  enemy arrow drains `player.half_hearts_per_hit` (half a heart) and
  grants `player.invuln_steps` (45) of invulnerability (the player
  blinks, and further hits are ignored while it lasts). The HUD draws
  the heart slots with the sheet's three frames: full, half-drained and
  fully gray. The last half-heart lost is fatal: the ordinary death
  flow runs (key drops, arrows cleared) and the respawn refills
  health. Falling into the void is an instant death regardless of
  health.
- **Stuck arrows are platforms** (embedded in vertical walls only), and
  arrows substep their flight so fast shots never skip a tile. Rope
  arrows are exempt (they anchor instead).
- **The rope pendulum.** Rope arrows (selected with the swap button)
  expire at `config.rope.max_range` in flight; when one sticks, the
  player attaches on the next step (one rope at a time, one attach per
  arrow). While attached, `Player.rope_step` handles winching and
  detaching (jump, lost anchor, arrow removal, death), and
  `Player.physics` applies the constraint: the outward radial velocity
  is removed before integration when the rope is taut (gravity keeps
  feeding the tangential swing), and the position is pulled back onto
  the rope circle after collision resolution. Detaching preserves
  velocity.

## The archer brain

Archers (`src/enemies.lua`) run a state machine: `patrol -> aim ->
volley -> (investigate | patrol)`.

- **Senses** (`Enemies.sees`): the player must be within
  `enemies.detect_distance`, in front of the archer (a back-turned
  archer is blind) and in clear line of sight — the eye -> player ray is
  sampled every `enemies.sight_step` px and terrain (solid tiles and
  slope wedges) blocks vision. No x-ray vision.
- **Aim**: on spotting, the archer stops moving and solves a ballistic
  arc to the player (`enemies.aim_steps` preparation, 2/3 of the
  original 30-step draw): flat arc first, then a loftier arc if terrain
  blocks the flat one, falling back to a straight shot. While aiming it
  re-solves each step and draws its solved trajectory (dots, like the
  player's aim preview; the arc stops where terrain would catch the
  arrow). If both arcs are blocked while the player is visible, the
  countdown holds until a clear arc exists.
- **Volley**: when the preparation timer lapses it releases
  `enemies.volley_count` arrows one at a time, `enemies.volley_stagger`
  steps apart (quick successive shots, not one simultaneous blast).
- **Rapid fire**: while the player stays visible the archer keeps
  shooting — after each volley it waits `rapid_min`..`rapid_min +
  rapid_extra` steps (semi randomized), then draws and fires again.
  The moment it loses the player — during a draw or between volleys —
  the cycle ends in an investigation.
- **Lost sight mid-aim**: the volley still fires at the last solved
  angle, then the archer investigates the last known position — walking
  toward it without stopping at ledges, for up to
  `enemies.investigate_timeout`, ending early within
  `enemies.investigate_reach` of the spot, or immediately when it
  re-spots the player (once its cooldown lapses). A drop deeper than
  `enemies.max_drop_tiles` (4 tiles) is refused: the archer decides to
  stay on its platform and the search ends there.
- **Backed perch**: an archer with a wall within two tiles behind it
  and a ledge within two tiles ahead holds the edge (stands still,
  facing out) instead of pacing back and forth in the box.

## Testing

Two gates keep regressions out:

1. **Snapshot baseline** — the deterministic scripted run (900 steps,
   snapshots every 30) diffed against `tests/trace_baseline.txt`, a trace
   captured from the current code. After an *intentional* gameplay
   change, regenerate the baseline and confirm the only diffs are the
   intended ones:

```sh
luajit tests/run.lua main.lua tests/trace_baseline.txt          # rebase
luajit tests/run.lua main.lua /tmp/trace.txt                    # verify
luajit tests/trace_diff.lua tests/trace_baseline.txt /tmp/trace.txt
```

2. **Behaviour suites** — `tests/enemies_test.lua` covers the archer
   senses (back-turned, wall-blocked, out-of-range), the aim state, the
   staggered three-arrow volley, the rapid-fire cadence, the
   investigate walk (roam exemption, deep-drop refusal, leaving the
   platform) and the backed-perch hold; `tests/player_test.lua` covers
   the hearts system (i-frame-gated melee drain, arrow hits, fatal
   refill, void death); `tests/rope_test.lua` covers the rope arrow
   (attach + hang, pendulum swing bounds, detach-preserving-velocity,
   winching, max-range expiry, platform exemption, swap, anchor loss):

```sh
luajit tests/enemies_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
```

`tests/legacy_main.lua` is the frozen pre-refactor monolith with a
test-only snapshot hook appended (inert in a real LÖVE run). It remains
available as a historical reference for the original simulation; as the
AI is deliberately overhauled, `trace_baseline.txt` (current code) is
the live regression gate.
