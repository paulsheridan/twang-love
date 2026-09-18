# twang architecture

A LÖVE 11 port of the twang pico-8 cart: a 480x320 native render (16x16
tiles and sprites, each an exact 2x2 upscale of the original 8x8 art) at
a 30hz fixed-timestep simulation with a smooth camera. Levels are Tiled
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
   sprites.lua            spritesheet quads + draw helper (flip/rot) -- 16x16
                          tiles, 2x2 upscales of the cart's 8x8 art
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
  e_arrows, enemies, particles, keys, locks, doors, switches, springs,
  winches
- `player` — the player body
- `die` — routes player deaths to `Player.die`; `hurt` routes damage to
  `Player.hurt` (systems never require `src/player.lua` for those;
  they call `ctx.die(ctx)` / `ctx.hurt(ctx)`)

Each sim step (`Game:step`, 1/30s) runs:

1. `input:step()` — press edges for this step
2. `Player.aim_step` — bow aiming, power levels, firing on release
3. a full physics pass **every** step: player physics, player arrows,
   enemies, enemy arrows, particles, spring timers, camera. Each pass
   advances world time by `ctx.dt` steps — 1 normally, or
   1/`config.aiming.slow_motion_steps` while aiming, which is the bow's
   slow motion: the world moves at 1/N speed but is simulated (and
   rendered) at the steady full framerate, so aiming never freezes the
   world into a slideshow. Everything world-time based (integrators,
   timers) scales with `ctx.dt`; real-time things (input cadence, bow
   turning) do not.

Rendering is a pure read of the same state: `render/blit.lua` draws the
world into the 480x320 canvas (world pass, then the player on top, then
the controls-panel overlay), blits it to the window preserving aspect,
and anchors the HUD to the blit rect. The blit scale is always a whole
number (letterboxing the remainder, fullscreen included), so game
pixels stay square and sharp at any window size; F11 toggles desktop
fullscreen. The window opens at `config.window.scale` (3x) and is
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
  speeds; all sprite/line/dot draw positions are floored, so nothing
  rasterizes unevenly on the pixel canvas (no shimmering edges). Vector
  primitives draw at 2x to match the 2x2-upscaled sheet: dots are 2x2
  pixel blocks (`dot` helpers in `render/world.lua` / `render/player.lua`)
  and world-pass lines are 2px thick (set in `render/blit.lua`).
- **The window fits its monitor.** `Game:fit_window` re-fits the window
  to an integer multiple of the 480x320 view whenever it lands on a
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
  tile's solidity; a closed door is also a bouncy surface like a sticky
  wall (`World.sticky_at` answers for doors), so arrows never embed in
  one and hang in the doorway after a switch opens it; springs are
  standable pads solid across the bottom
  `springs.pad_height` px of their tile (matching the inactive sprite's
  pad, so bodies stand on it instead of hovering), with `resolve_y`
  landing bodies on the pad surface; switch tiles are recessed (arrows
  fly in, bodies don't). Switches that drive springs are momentary —
  they pop back to inactive when every spring of their group has reset,
  so they can be shot again; every strike flips a switch on<->off.
- **Phase tiles flip with phase-switch strikes.** Tiles flagged `phase`
  on the tileset (one designated tile per level, e.g. the platform ring,
  tile 135) all toggle solid<->non-solid together on a strike of a
  switch carrying the bool `phase` property (the level's `switch_pform`
  trio), regardless of that switch's group; spring and door switches
  never touch the blocks. While non-solid they collide with
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
  grants `player.invuln_steps` (45) of invulnerability (blood sprays
  opposite the impact, and a translucent red silhouette overlay fades
  out over the shield's last `shield_tint_fade_steps` — the old blink
  hid the player during slow motion; further hits are ignored while the
  shield lasts). An enemy arrow that lands rests at its impact point
  for `arrows.player_stick_frames` before vanishing. The HUD draws
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
- **The winch** (motorized rope reel). A rope arrow whose tip enters a
  winch's box is consumed on impact and the player is attached to the
  winch instead (`p.winch`): `Player.physics` overrides the velocity
  with a pull straight toward the winch centre that accelerates by
  `config.winch.reel_accel` per step up to `max_reel_speed` (after
  gravity/walk logic, so nothing fights the motor; the rope pendulum is
  inert — `p.rope` is nil — and a rope line is still drawn from the
  winch to the player). The reel is unstoppable: jump presses do
  nothing (no jump buffer either). Once the player's centre is within
  `config.winch.pass_radius` of the winch centre the reel cuts the line
  and throws them on through the centre, out the opposite side from
  the one they hit it from, at `max(reel speed, min_throw_speed)`. The
  throw direction is **carried from the entry side**: the winch stores
  the unit vector toward itself at capture and refreshes it every reel
  step while the player is still outside the pass radius, so a final
  reel step that overshoots the centre cannot invert the throw
  (recomputing the radial at release threw ~11% of long approaches
  back the way they came — the player "stopped dead" or was flung
  backwards). The escape hatch is firing: `Arrows.fire` cancels a
  winch reel. Death clears it; non-rope arrows ignore the winch (the
  entity is solid to nobody). Movement input is ignored through the
  reel and for `config.winch.stick_grace` steps after the release (no
  acceleration, no damping, no walk cap — the throw's physics play out
  untouched; the grace ends early once the player lands), and
  `p.rope_cd` covers the same window so a leftover stuck rope arrow
  cannot re-grab the player and eat the momentum mid-arc.
  `config.winch.debug` enables `src/winchlog.lua` to append a per-event
  trace (capture/reel/release/grace, including the entry-vs-throw dot)
  to `winch_debug.txt` in the LÖVE save directory.

## The archer brain

Archers (`src/enemies.lua`) run a state machine: `patrol -> aim ->
volley -> (cover fire | investigate) -> patrol`. All three enemy types
share the tracking model: **the player's position is refreshed into
`last_known` every step it is visible**, in every state (patrol, aim,
the rapid-fire wait, cover fire and searches included), so a shot fired
after sight breaks aims at the freshest known spot.

- **Senses** (`Enemies.sees`): the player must be within
  `enemies.detect_distance`, in front of the archer (a back-turned
  archer is blind) and in clear line of sight — the eye -> player ray is
  sampled every `enemies.sight_step` px and terrain (solid tiles and
  slope wedges) blocks vision. No x-ray vision.
- **Aim**: on spotting, the archer stops moving and solves a ballistic
  arc to the player (`enemies.aim_steps` preparation, 1/3 of the
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
- **Cover fire**: the moment line of sight breaks — mid-draw or between
  volleys — the archer keeps firing at the last known position on the
  same cadence for `enemies.suppress_steps` (3s), holding its ground.
  A shot already mid-telegraph still fires at its last solved angle.
  After the window lapses it investigates the last known position —
  walking toward it without stopping at ledges, for up to
  `enemies.investigate_timeout`, ending early within
  `enemies.investigate_reach` of the spot. A drop deeper than
  `enemies.max_drop_tiles` (4 tiles) is refused: the archer decides to
  stay on its platform and the search ends there.
- **Re-engage**: seeing the player again — during cover fire or a
  search — returns to combat at once (the shoot cooldown only gates a
  patroller's first spot).
- **Backed perch**: an archer with a wall within two tiles behind it
  and a ledge within two tiles ahead holds the edge (stands still,
  facing out) instead of pacing back and forth in the box.

The laser rifleman shares this brain verbatim (`ranged_brain` with a
per-type spec: aim solve, telegraph length, cadence, shot release), so
future ranged enemies inherit the whole loop.

## The laser rifleman brain

Laser riflemen (`src/enemies.lua`) run the shared `ranged_brain` — the
archer's skeleton (same senses, same cover-fire/investigate loop) with
a beam weapon instead of a ballistic volley.

- **Aim**: on spotting, the rifleman stops, locks a unit fire direction
  at the player and re-tracks it every step the player stays visible.
  The shot is telegraphed with a **blinking laser sight**: a thin red
  line from the muzzle to the player's centre, blinking on/off every
  `enemies.laser_sight_blink` steps for `enemies.laser_sight_steps`
  (a quicker draw than the archer's, 0.6s) before firing.
- **Beam**: when the telegraph lapses the beam fires along the last
  solved direction, marched out (`enemies.laser_ray_step` sampling) to
  the first wall — anything arrows cannot fly through (doors included,
  arrow slits excluded) or a slope wedge — or to the world's edge. **A
  beam that would reach the player stops dead at them instead**: the
  slab test's entry distance caps the beam's length, so it never draws
  through them. The whole flash lives for `enemies.laser_beam_steps`
  (5 frames — over in a blink), drawn as a thick red ribbon around a
  hot white core. On impact the contact point throws
  `particles.spark_count` spark flecks (alternating yellow/white,
  bouncing back along the beam, away from the shooter) on top of the
  usual blood spray, and the hit lands right away:
  `enemies.laser_half_hearts` (2 — a full heart) with the usual i-frame
  shield. A player who walks into a live flash stops it the same way;
  the beam's own `hit` flag keeps the sparks to one burst per shot.
- **Bursts**: each charge holds `laser_burst_count` (3) shots. Once the
  first beam lands the next shots follow on the short burst cadence
  (`laser_burst_min`..`+laser_burst_extra`, each with its own quick
  telegraph, re-tracking the visible player) — no full recharge in
  between. Only once the budget is spent does the
  `laser_rapid_min`..`+laser_rapid_extra` recharge apply before the
  next charge. Sight breaks mid-burst spend the budget (the cover-fire
  window is blind anyway); re-spotting opens a fresh one.
- **Rapid fire / cover fire**: the archer's loop with the slower
  recharge numbers between charges. Sight breaks open the same
  cover-fire window (blind shots at the last tracked spot, full
  telegraph included), then the search.
- **The enemies toggle** (test menu) disarms a firing laser along with
  the archers: live beams go out and the brain drops back to patrol.

## The melee brain

Melee enemies (`src/enemies.lua`) gain a small brain: `patrol -> chase
-> investigate`.

- **Chase**: a visible player is sprinted after at
  `enemies.melee_chase_speed` (2.5 px/step — pressure, but outrunnable),
  target refreshed from `last_known` every visible step.
- **Search**: on sight break the chase becomes a patrol-pace walk to
  the last known spot (`investigate_timeout`/`investigate_reach`); a
  drop deeper than `max_drop_tiles` is refused and ends the walk.
- **Re-engage**: seeing the player again returns to the chase at once;
  the search timing out or arriving settles back to patrol. Contact
  kill is unchanged (it happens before the brain, as before).

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
   staggered three-arrow volley, the rapid-fire cadence, the cover-fire
   window (blind volleys at the last known spot, holding ground,
   re-engaging on sight, handing over to the search), continuous
   last-known tracking, the cooldown-free re-engage, the investigate
   walk (roam exemption, deep-drop refusal, leaving the platform), the
   backed-perch hold and the melee brain (chase speed, search, re-chase,
   deep-drop refusal); `tests/laser_test.lua` covers
   the laser rifleman (spot -> blink-aim fields, telegraph expiry
   firing, the wall-stopping beam march, the full-heart hit and its
   i-frame single-hit rule, the last-known-spot shot that misses a
   fleeing player, wall-blocked sight, the slower cadence and the
   toggle disarm); `tests/player_test.lua` covers
   the hearts system (i-frame-gated melee drain, arrow hits, fatal
   refill, void death); `tests/rope_test.lua` covers the rope arrow
   (attach + hang, pendulum swing bounds, detach-preserving-velocity,
   winching, max-range expiry, platform exemption, swap, anchor loss):

```sh
luajit tests/enemies_test.lua
luajit tests/laser_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
```

`tests/legacy_main.lua` is the frozen pre-refactor monolith with a
test-only snapshot hook appended (inert in a real LÖVE run). It remains
available as a historical reference for the original simulation; as the
AI is deliberately overhauled, `trace_baseline.txt` (current code) is
the live regression gate.
