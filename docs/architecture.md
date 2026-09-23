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
   rockets.lua            the rocketeer's homing rockets: spawn, pursuit
                          steering, proximity/terrain/lifetime fuse, blasts
                          (plus the explosion flashes they leave behind)
   bombs.lua              the bomber's thrown explosives: straight-line
                          flight, the thrower's crude timed fuse, flak
                          proximity bursts over an airborne player,
                          grenade bounces over one on the ground
   interactables.lua      key/lock/door/switch/spring puzzle logic
   save.lua               per-level best time/grade, persisted to the
                          LÖVE save directory (no-op headless)
   particles.lua          poofs, blood, sparks, smoke and explosion bursts
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
     hearts.lua           heart slots (full/half/empty), top-left
     hud.lua              level clock + power indicator + control hints
     menu.lua             controls panel overlay
     levelselect.lua      launch level-select panel (grades, locks)
     results.lua          level-clear results panel
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
  e_arrows, enemies, rockets, bombs, particles, keys, locks, doors,
  switches, springs, winches
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

**Boot mode.** The game boots into the default level (`config.map_file`)
but opens on the **launch level select** over the paused world
(`Game:select_step`; rows from `config.levels` minus `hidden` entries,
held on `Game.select_levels`). Confirming always performs a fresh
`Game:load_level` and resumes. The test menu's last row returns to the
select. The headless harness passes `skip_select` to `Game.new`
(main.lua, when `TWANG_TEST` is set) and boots straight into play, so
the scripted gates stay simulation-only.

**Completion.** A level's exit entities (`ents.exits`, the `exit` kind)
are touch-checked at the end of `Game:step`; the first player overlap
runs `Game:complete_level`: the run's clock (`Game.play_steps`, real
30hz steps) and death count (`ctx.die` is wrapped at level load to count
`Player.die` calls) are graded against the level's `gold`/`par` times,
recorded via `src/save.lua` (best time strictly, best grade
independently, keyed by map file) and the world freezes on the results
panel (`mode == "complete"`, `Game:complete_step`). Action continues to
the next visible level (the level select after the last), swap replays
the same level fresh. The level select gates each row on the previous
row's recorded clearance (`Save.cleared`), lifted by the test menu's
unlock-all toggle.

**Rooms.** Levels can be split into camera-framed rooms (`room`
rectangles in the Tiled map — `docs/tiled-format.md`). The world stays
one grid; a room's job is to clamp the camera (`World:clamp_rect` drives
`Camera.clamp`/`snap`), scope the foreground fade (per-room alphas) and
gate simulation: only entities inside the active room step (guards in
the enemies/arrows/rockets/bombs/particles/springs loops, `World:in_room`),
so off-room enemies freeze mid-state and resume on re-entry. Crossing a
border (hysteresis-checked, `World:room_target`) runs a fade wipe in
`Game:step`: fade out, switch the room and snap the camera at full
black, fade in. Roomless maps reduce every path to the pre-rooms
behavior — one implicit room, whole-map clamping, everything simulates —
which is what keeps the trace baseline stable.

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
volley -> (cover fire | investigate) -> patrol`. All four enemy types
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
future ranged enemies inherit the whole loop. (Doc note: the laser's
aim now **locks** when the sight line first flashes — the telegraph
line and the beam that follows share one locked vector, and a player
who moves mid-flash cannot bend the shot.)

## The laser rifleman brain

Laser riflemen (`src/enemies.lua`) run the shared `ranged_brain` — the
archer's skeleton (same senses, same cover-fire/investigate loop) with
a beam weapon instead of a ballistic volley.

- **Aim**: on spotting, the rifleman stops and **locks a unit fire
  direction** at the player the moment the telegraph begins — the aim
  stays locked through the telegraph, so the flashing sight line and
  the beam that follows fire along the same vector, and a player who
  moves mid-flash cannot bend the shot. The shot is telegraphed with a
  **blinking laser sight**: a thin red line from the muzzle out along
  the locked direction (to where the beam would reach), blinking on/off
  every `enemies.laser_sight_blink` steps for
  `enemies.laser_sight_steps` (a quicker draw than the archer's, 0.6s)
  before firing.
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
  telegraph locked at that telegraph's start) — no full recharge in
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

## The rocketeer brain

Rocketeers (`src/enemies.lua` + `src/rockets.lua`) run the shared
`ranged_brain` — the archer's skeleton with a homing rocket launcher
instead of a ballistic volley. Their ordnance is the game's first
projectile that hunts on its own: cover does not protect against it,
and shooting the rocket down is the counterplay.

- **Aim**: on spotting, the rocketeer stops and charges the shot behind
  a **blinking telegraph** (dotted red sparks rising from its head,
  same blink math as the laser sight: `rocket_aim_steps` /
  `rocket_sight_blink`). There is no ballistic solve — the launch is
  always straight up, so the brain only tracks and turns to face.
- **Launch**: one rocket spawns **just above the shooter's head** and
  goes straight up (a `rocket_jitter`-sized random heading offset keeps
  salvos from stacking perfectly). Rockets live in `ents.rockets`,
  stepped by `Rockets.update` after the enemies pass (global airborne
  cap: `rocket_max_alive`).
- **Climb, hover, strike**: a rocket carries a unit heading and flies
  in three phases. It **climbs** straight up (no steering) until it has
  risen `rocket_hover_height` (24px) above the launch point, then
  **hovers** — velocity zero, nose up, smoking — for
  `rocket_hover_steps` (12, 0.4s): the player's window to shoot it down
  while it hangs. When the hover lapses it **turns on a dime**: the
  heading snaps to the player's live centre and the cruise begins.
- **Homing**: a rocket cruises at a constant `rocket_speed`, rotating
  its heading toward the player's **live centre** up to
  `rocket_turn_rate` per step — pure pursuit, so the flight bends into
  an arc (turn radius = speed / turn rate ≈ 80px). Sight is irrelevant
  once airborne: a rocket keeps hunting even after the shooter loses
  the player, arcing over walls to reach them behind cover.
- **Fuse**: flight is substepped (`rocket_substep` sampling) so fast
  turns never skip a wall. A rocket detonates when it gets within
  `rocket_proximity` (12px) of the player's centre (a player who jumps
  into a hovering rocket pops it too), touches terrain
  (`solid_for_arrow`/slopes — just short of the wall, not inside it), or
  reaches `rocket_lifetime`; flying off the world just removes it. A
  grey `Particles.smoke` trail puffs behind the tail.
- **Explosion** (`Rockets.explode`): an expanding flash ring
  (`ents.booms`, `boom_frames` long, drawn out to the blast radius)
  around a white core, a red/orange `Particles.boom` spark burst and a
  poof. Damage is a circle-vs-box test at `rocket_blast_radius`: the
  player takes `rocket_half_hearts` (2 — a full heart, i-frames
  respected); **any enemy caught in the blast dies instantly** (arrows
  are the game's only other killer, and they remove instantly too) —
  including the launcher itself if it fires under a low ceiling.
  Other rockets are unaffected (no chain reactions).
- **Arrow detonation**: a player arrow tip that touches a rocket
  (generous `rocket_hit_w`/`rocket_hit_h` box at its centre, any arrow
  kind) detonates it right there — the arrow is consumed like an enemy
  hit. The hover phase exists to make that read: a hanging rocket is a
  sitting target. Blasting a rocket at arm's length still catches the
  player in the blast, so shooting them down early matters.
- **Bursts / cover fire / toggle**: the laser's numbers with
  `rocket_*` knobs — 2 rockets per charge on the short cadence (each
  with its own telegraph, tracking the visible player), the long
  recharge between charges, blind cover fire at the last known spot,
  and the enemies toggle clearing rockets and booms from the air.

## The bomber brain

Bombers (`src/enemies.lua` + `src/bombs.lua`) run the shared
`ranged_brain` — the archer's skeleton with a thrown explosive instead
of a ballistic volley. Their ordnance is the game's cheap shot: the
thrower deliberately guesses the fuse instead of solving it, so bursts
land near-but-not-on the target and a player who keeps moving stays
hard to pin.

- **Aim**: on spotting, the bomber stops and charges the throw behind a
  **blinking telegraph** (a raised orange bomb dot with a flickering
  white fuse spark above its head, same blink math as the laser sight:
  `bomber_aim_steps` / `bomber_sight_blink`). No ballistic solve — the
  throw is read off the live target when the telegraph lapses.
- **Throw**: one bomb spawns **just above the shooter's head** and
  flies in a **straight line** (no gravity, no steering) at the last
  known spot at a constant `bomb_speed`. Bombs live in `ents.bombs`,
  stepped by `Bombs.update` after the rockets pass (global airborne
  cap: `bomb_max_alive`).
- **The crude fuse**: the bomber picks the detonation time it *thinks*
  will catch the player — straight-line distance to the target over
  throw speed, floored to whole steps, then jittered
  ±`bomb_fuse_error` (8) steps. Deliberately inaccurate but
  inexpensive: no trajectory integration, no terrain march, no
  intercept solve — against a moving player the burst usually lands
  short or behind.
- **Flak / grenade**: the fuse burns wherever the bomb is, and the
  player's grounded state picks the burst style live. While the player
  is **airborne** the bomb bursts like **flak**: proximity to their
  live centre within `bomb_flak_proximity` (14px) pops it early — the
  jump that clears a throw still gets caught in the air-burst. Over a
  **grounded** player it acts like a **grenade**: no proximity check at
  all, the body flies (or bounces) on and the timer alone decides the
  burst point.
- **Bounce**: flight is substepped (`bomb_substep` sampling) so a fast
  throw never skips a tile. Terrain contact (anything arrows cannot fly
  through, plus slopes) **bounces the grenade body instead of
  detonating** — the hit axis reflects and both axes damp by
  `bomb_bounce_damp` (0.5), a bounce slower than `bomb_rest_speed`
  rests the bomb where it lies (fuse still burning). Flying off the
  world just removes it.
- **Explosion**: detonates through the **shared blast** with bomb
  knobs — the flash ring rides the boom entry's own radius (rockets
  and bombs differ), the spark/poof burst, `bomb_blast_radius` (24px)
  circle-vs-box damage: the player takes `bomb_half_hearts` (2 — a
  full heart, i-frames respected); **any enemy caught in the blast
  dies instantly**, the launcher included.
- **Arrow detonation**: a player arrow tip that touches a bomb in
  flight (generous `bomb_hit_w`/`bomb_hit_h` box, any arrow kind)
  detonates it right there — the arrow is consumed like a rocket hit.
- **Bursts / cover fire / toggle**: the laser's numbers with
  `bomber_*` knobs — 2 bombs per charge on the short cadence (each
  with its own telegraph, tracking the visible player), the long
  recharge between charges, blind cover fire at the last known spot,
  and the enemies toggle clearing bombs from the air.

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
   the laser rifleman (spot -> blink-aim fields, the locked aim that
   survives a moving player, telegraph expiry firing, the wall-stopping
   beam march, the full-heart hit and its i-frame single-hit rule, the
   last-known-spot shot that misses a fleeing player, wall-blocked
   sight, the slower cadence and the toggle disarm);
   `tests/rocketeer_test.lua` covers the rocketeer
   (spot -> blink-aim fields, the straight-up launch just above the
   head, homing that keeps chasing a player behind the shooter's back,
   the proximity-fuse full-heart blast, ceiling detonation just short
   of the wall, arrow-tip detonation with the blast's enemy kill, the
   2-rocket burst cadence, the airborne cap and the toggle disarm);
   `tests/bomber_test.lua` covers the bomber (spot -> blink-aim
   fields, the straight-line throw from above the head with the crude
   jittered fuse estimate, the grenade timer burst that a dodging
   grounded player escapes, the flak proximity burst over an airborne
   player, the never-proximity rule over a grounded one, the damped
   grenade bounce with the fuse still burning, arrow-tip detonation
   with the blast's enemy kill, the 2-bomb burst cadence, the airborne
   cap and the toggle disarm); `tests/player_test.lua` covers
   the hearts system (i-frame-gated melee drain, arrow hits, fatal
   refill, void death); `tests/rope_test.lua` covers the rope arrow
   (attach + hang, pendulum swing bounds, detach-preserving-velocity,
   winching, max-range expiry, platform exemption, swap, anchor loss);
   `tests/results_test.lua` covers the completion flow (exit touch ->
   results, grade thresholds, best time/grade recording, results-panel
   inputs, next-level/replay flow, death counting):

```sh
luajit tests/enemies_test.lua
luajit tests/laser_test.lua
luajit tests/rocketeer_test.lua
luajit tests/bomber_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
luajit tests/menu_test.lua
luajit tests/levelselect_test.lua
luajit tests/foreground_test.lua
luajit tests/rooms_test.lua
luajit tests/results_test.lua
```

`tests/legacy_main.lua` is the frozen pre-refactor monolith with a
test-only snapshot hook appended (inert in a real LÖVE run). It remains
available as a historical reference for the original simulation; as the
AI is deliberately overhauled, `trace_baseline.txt` (current code) is
the live regression gate.
