# twang architecture

A LÖVE 11 port of the twang pico-8 cart: a 320x180 native render (8x8
terrain tiles over the untouched 2x2-upscaled sheet; 16x16 entity art
cells, each an exact 2x2 upscale of the original 8x8 art) at a 60hz
fixed-timestep simulation with render interpolation and a smooth
camera. World time is measured in 30hz-steps (the pico-8 cart's tick):
`ctx.dt = 30/sim.rate` per sim tick, so the per-step tuning constants
are rate-invariant and the rate knob can move without retuning. Levels
are Tiled JSON maps (format documented in `docs/tiled-format.md`).

## Layout

```
main.lua                 thin bootstrap: forwards LÖVE callbacks to the game
conf.lua                 window setup, driven by src/config.lua
src/
  config.lua             every gameplay/rendering constant, in one place
  game.lua               orchestrator: owns state, runs the 30hz sim, renders
  input.lua              input state with pico-8 button semantics (btn/btnp)
  world.lua              tile grid, tile flags, solidity queries
  level.lua              level assembly: scans Tiled objects into entity lists
   player.lua             player physics, bow aiming/firing, key carrying,
                          rope pendulum (attach/detach/winch), the
                          wall-run over runnable bands
    arrows.lua             player + enemy arrows (flight, bounce, stick, hits);
                           rope arrows (range, anchoring); the bomb arrow's
                           contact detonation + blast (detonate_bomb);
                           the pusher's strike (trigger_pusher); also
                           exposes simulate_path and the shared
                           zone-driven shove (shove)
    enemies.lua            melee patrol; archers with a sense -> aim -> volley ->
                           investigate brain; patrols bounded by roam_tiles
    rockets.lua            the rocketeer's homing rockets: spawn, pursuit
                           steering, proximity/terrain/lifetime fuse, blasts
                           (plus the explosion flashes they leave behind)
    bombs.lua              the bomber's thrown explosives: straight-line
                           flight, the thrower's crude timed fuse, flak
                           proximity bursts over an airborne player,
                           grenade bounces over one on the ground
    spirit.lua             the bow's spirit arrow: a fire-time burst of
                           ghostly force at the player's centre that
                           flings the body opposite the aim (no
                           projectile at all -- the fling, the burst
                           particles and the ghost tint are the whole
                           effect)
   interactables.lua      key/lock/door/switch/spring puzzle logic
   movers.lua             moving blocks: grid-aligned platforms that
                          travel a line and pause at each end; the
                          auto cycler and the stand/arrow-triggered
                          lift (rider carry, stalls, no crush)
   save.lua               per-level best time/grade, persisted to the
                          LÖVE save directory (no-op headless)
   particles.lua          poofs, blood, sparks, smoke, explosion bursts,
                          heavy-hit debris shards, scorch chunks and the
                          burning aftermath anchored at impact sites
     camera.lua             smooth follow, clamped to the world; the
                            frame never shakes (a pure damped follow)
   sprites.lua            spritesheet quads + draw helper (flip/rot) --
                          16x16 art cells; 8px terrain sub-tile quads
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

- `world` — the tile grid + flags (from `src/world.lua`),
  created from the loaded Tiled map and the interactable entity lists
- `ents` — live entity lists from `src/level.lua`: spawn_points, arrows,
  e_arrows, enemies, rockets, bombs, particles, keys, locks, doors,
  switches, springs, winches. (The spirit arrow adds none: it fires no
  projectile.)
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
world into the 320x180 canvas (world pass, then the player on top, then
the controls-panel overlay), blits it to the window preserving aspect,
and anchors the HUD to the blit rect. The blit scale is always a whole
number (letterboxing the remainder, fullscreen included), so game
pixels stay square and sharp at any window size; F11 toggles desktop
fullscreen. The window opens at `config.window.scale` (3x) and is
resizable — the blit re-fits every frame.

**Boot mode.** The game boots into the default level (`config.map_file`)
but opens on the **launch level select** over the paused world
(`Game:select_step`; rows from `config.levels` minus `hidden` entries,
held on `Game.select_levels`; rows flagged `debug` are workshop
sandboxes — always unlocked and outside the ladder's progression chain,
which `Game:next_entry` also skips). Confirming always performs a fresh
`Game:load_level` and resumes. The test menu's last row returns to the
select. The headless harness passes `skip_select` to `Game.new`
(main.lua, when `TWANG_TEST` is set) and boots straight into play, so
the scripted gates stay simulation-only.

**Completion.** A level's exit entities (`ents.exits`, the `exit` kind)
are touch-checked at the end of `Game:step`; the first player overlap
runs `Game:complete_level`: the run's clock (`Game.play_steps`, sim
ticks; seconds = ticks/rate) and death count (`ctx.die` is wrapped at level load to count
`Player.die` calls) are graded against the level's `gold`/`par` times,
recorded via `src/save.lua` (best time strictly, best grade
independently, keyed by map file) and the world freezes on the results
panel (`mode == "complete"`, `Game:complete_step`). Action continues to
the next visible level (the level select after the last), swap replays
the same level fresh. The level select gates each row on the previous
row's recorded clearance (`Save.cleared`), lifted by the test menu's
unlock-all toggle.

**Checkpoints.** Checkpoint flags (`ents.checkpoints`, kind
`checkpoint`) are touch-checked in `Player.physics`: the first overlap
becomes `ctx.checkpoint` (a small poof marks it) and `Player.die`
respawns there until another flag is touched. Without a touched flag,
deaths respawn at a random spawn point — the legacy behaviour, so
checkpointless maps are unchanged.

**The generated levels.** The v1 ladder's eight maps are emitted by
`tools/build_level.lua` (a level DSL over the Tiled JSON format —
terrain vocabulary: orange grass surface 36 over dark fill 2, orange
blocks, sticky pebbles, the phase block, arrow slits); the maps carry no
Background layer, so the void behind everything is the flat sky blue of
`config.world.sky` (the renderer skips `World.bg_map` entirely);
`tools/render_map.py` renders any map to a sprite-accurate PNG for
authoring QA.

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
  to an integer multiple of the 320x180 view whenever it lands on a
  different display (monitors differ in resolution and DPI scale, which
  otherwise leaves an oversized window for the WM to clamp — blurry,
  letterboxed). The blit always scales by a whole number.
- **Sub-frame input taps are never lost.** Held state is polled once per
  rendered frame, but press edges are evaluated once per sim step;
  key/gamepad press events additionally latch so a tap shorter than one
  rendered frame still fires. `btnp` repeats pico-8 style (every 4 steps
  after 15 held). Action buttons read `Input:pressed_fresh` (the first
  step of a press only, repeats excluded): jump buffering (one press is
  one jump — landing while holding it stays grounded), the arrow-kind
  cycle (one press, one kind) and the test menu's row toggles. Menu
  cursor movement keeps the repeat — that is what it is for.
- **Firing deafens the analog stick briefly.** An arrow shot
  (`Player.aim_step`'s release branch) calls
  `Input:ignore_stick(aiming.stick_ignore_frames)`: the stick's movement
  and aim readings drop out for that many rendered frames (keyboard and
  physical buttons keep working), so the bow hand's aim deflection
  cannot lurch the body the step the bow releases. The fire lands
  mid-update, after that frame's poll, so the release step also drops
  the movement buttons the stick drove (from `Input.axis_held`).
- **Mid-loop resets.** Player death clears the arrow list (and rockets,
  bombs, enemy arrows); the update loops read the list
  fresh each iteration and bail out when it is reset mid-loop. Player
  respawn reuses the same player table.
- **Jump corner forgiveness.** When a rising body clips a ledge with
  exactly one head corner, `resolve_y` slides it horizontally around
  the corner (up to `player.corner_nudge_px`, destination head corners
  verified free) instead of snapping below the cell and zeroing the
  velocity — jumps taken under ledges reach their full height. Both
  corners covered (a real overhang) or a blocked/over-cap slide falls
  back to the normal head bump. Inert for enemies, which never move
  upward.
- **Doors and springs own their 16px art blocks** (a 2x2 run of 8px
  cells). A door's state alone decides its block's solidity; a closed
  door is also a bouncy surface like a sticky wall (`World.sticky_at`
  answers for doors), so arrows never embed in one and hang in a
  doorway after a switch opens it; springs are **landing pads**: solid
  across the bottom `springs.pad_height` px of their art block
  (matching the inactive sprite's pad, so bodies stand on it instead of
  hovering), with `resolve_y` landing bodies on the pad surface — and the pad FIRES ITSELF on the landing edge: every landing
  that touches a spring pad extends it and vaults the body
  (`Interactables.spring_vault`). Switch strikes no longer touch
  springs. Switch blocks are recessed (arrows fly in, bodies don't).
  Switches that drive doors stay momentary-free: every strike flips a
  switch on<->off and re-evaluates its group's doors; only switches
  flagged `phase` flip the blocks.
- **Phase tiles flip with phase-switch strikes.** Cells flagged `phase`
  on the tileset (one designated art cell per level, e.g. the platform ring,
  art cell 135) all toggle solid<->non-solid together on a strike of a
  switch carrying the bool `phase` property (the level's `switch_pform`
  trio), regardless of that switch's group; door switches never touch
  the blocks. While non-solid they collide with
  nothing (bodies, arrows) and render translucent (`phase.alpha`).
  `World.phase_solid` is the single state flag, checked in
  `solid_at` and the map draw; spring pop-backs don't flip it (springs
  don't answer switches any more) — only arrow strikes do.
- **One-way platforms.** Cells flagged `oneway` (the blue thin slat,
  art 64; tileset property, gff bit 5) are standable from above only:
  `resolve_y`'s downward pass runs `World:oneway_catch` — the feet's
  SWEPT span (previous feet from the render-stamp `_py`; a full-speed
  9px/step fall can cross a whole 8px tile in two steps, so the swept span
  is what counts) crossing into an oneway cell's row snaps the body to
  the cell's top edge. Everything else passes through: the cell is not
  `solid`, so rising bodies jump through from below, arrows fly through
  (`solid_for_arrow`), enemy sight and laser beams see past it, and
  enemies treat it as open air (their ledge probes read `solid_at`).
  There is no drop-through. Standing on one is ground (`gr` set, no
  friction quirk).
- **The archer brain** (below) runs archers; melee enemies just patrol.
- **Patrols are bounded.** Every enemy patrols at most
  `enemies.roam_tiles` (10 art tiles) from its spawn anchor (`home_x`,
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
  shield lasts). **Heavy hits read as set pieces**: a laser beam hit or
  a rocket/grenade blast catching the player also throws chunky debris
  (`Particles.shards`, `particles.shard_count` random-sized grey/white/
  orange chunks, longer-lived than the blood) off the impact point.
  An enemy arrow that lands rests at its impact point
  for `arrows.player_stick_frames` before vanishing. The HUD draws
  the heart slots with the sheet's three frames: full, half-drained and
  fully gray. The last half-heart lost is fatal: the ordinary death
  flow runs (key drops, arrows cleared) and the respawn refills
  health. Falling into the void is an instant death regardless of
  health.
- **Impacts are asymmetric on purpose.** Enemy projectiles landing on
  terrain are set pieces: an enemy arrow burying itself, a rocket
  detonating against a wall, a grenade cracking a surface on each
  bounce and a laser beam slamming into whatever stops it all throw
  scorched chunks off the struck surface (`Particles.scorch`, dark grit
  with embers, sprayed back off the impact). The player's own arrows
  deliberately spawn nothing when they hit terrain — their hits stay
  small and quiet against the enemies' carnage (the game never damages
  level geometry either; the chunks are pure dressing). Everything that
  appends to `ents.booms` (rockets, grenades, the bow's bomb arrows, the
  pusher's flash ring) draws its flash ring and throws particles, and
  that is the whole of the effect: **the camera never shakes**, enemy
  detonations included. `Camera` is a pure damped follow of the
  player's clamped target, with no offset applied anywhere, so every
  boom — the bow's included — lands in a frame that does not move.
- **Burning aftermath.** A laser's wall end — or any blast anchored
  close to terrain (the `ents.burns` probe checks the eight surrounding
  directions for the nearest surface within 24px) — leaves a short-lived
  **burning spot** pinned to that face: for `particles.aftermath_steps`
  (~1.3s) it keeps spitting spark flecks off the burnt surface on a
  jittered cadence (`Particles.update_burns`), and near-wall blasts add
  black smoke drifting up (near-zero-gravity particles, `after_smoke_g`,
  dark grey with near-black mix). These are stand-ins for the impact
  art to come, like the boom flash; a blast in open air leaves no
  remains, and laser spots spark without smoking.
- **Stuck arrows bury their tip, and the terrain buries them back.**
  On a stick the tip is set `arrows.embed_px` (2px, a quarter tile) *into*
  the surface it struck, so the arrow reads as driven into the world
  rather than resting against it, and `draw_stuck_arrows` runs before
  `draw_map` so the tiles paint over that buried length. The recorded
  face (`a.face` for walls) is unchanged by the embed, so the perch
  below still measures against the tile edge. A rope anchored to a
  buried arrow starts its line at the surface (`tip - heading *
  embed_px`), not at the tip, so the rope never lies across the wall.
- **Impact leaves the shaft buckled.** The drawn shaft of an embedded
  arrow is two segments meeting at a kink a little way back from the
  tip: the kick scales with the impact speed
  (`min(bend_max_px, max(0, speed - bend_speed) * bend_scale)`, so a
  soft tap lands dead straight and a full-power hit visibly buckles) and
  is capped at a couple of pixels. It is pure render geometry off the
  arrow's own retained `sdx`/`sdy` heading and impact velocity — no new
  sim field, and no `math.random` call (which would shift the traced RNG
  stream and every enemy decision downstream of it); which way it kinks
  rides the tile the arrow sits in.
- **Stuck arrows in walls are perches** (see the arrow-perch bullet
  below), not ground, and arrows substep their
  flight so fast shots never skip a cell. Rope arrows are exempt (they
  anchor instead).
- **A shot out the far side bleeds too.** A direct arrow hit on an
  enemy throws blood **twice**: the existing `Particles.blood` spray at
  the entry wound, thrown back out the way the arrow came in, and
  `Particles.blood_exit` at the point the shot *leaves* the body, thrown
  **along** the travel — the same cone, the same `blood_count`, 180
  degrees apart. The exit point comes from an analytic slab walk of the
  arrow's AABB along its **live** heading (the arc has turned since the
  bow released it, so the launch heading is not the heading that
  matters), and both sprays share one emitter, so the entry spray's
  distribution is untouched. The two together read as *the shot went
  through* rather than stopping at the near edge. Applies to every arrow
  kind that takes the enemy branch.
- **Rope attach is range-checked.** A stuck rope arrow only attaches
  when the player sits within `rope.max_length` of the anchor at attach
  time — farther anchors are ignored (the pendulum length-clamp used to
  yank the player across the map onto them).
- **The rope pendulum.** Rope arrows (selected with the swap button)
  expire at `config.rope.max_range` in flight; when one sticks, the
  player attaches on the next step (one rope at a time, one attach per
  arrow). While attached, `Player.rope_step` handles winching and
  detaching (jump, lost anchor, arrow removal, death), and
  `Player.physics` applies the constraint: the outward radial velocity
  is removed before integration when the rope is taut (gravity keeps
  feeding the tangential swing), and the position is pulled back onto
  the rope circle after collision resolution. While airborne on the
  rope the walk motor's air damping stands down (the swing coasts —
  only gravity and the constraint own its speed); left/right input
  still pumps. Detaching preserves
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
- **The wall-slide.** While airborne, falling (`vy > 0`) and against a
  wall (`check_walls`, which `solid_at` answers for: doors, movers and
  pushers all count), the body presses itself against the wall
  automatically — no held input — and descends at `player.slide_speed`
  instead of full speed; pushing the direction AWAY from the wall
  releases. There is no grab and no climb. A fresh jump press while
  sliding launches a **wall leap**: up at the jump speed and away from
  the wall at `player.walljump_push`. Blocked while a rope, winch,
  wall-run or arrow perch owns the body.
- **Arrow perches catch falls, not ground.** A stuck (non-rope) arrow
  catches a falling player as a PERCH (`p.arrow_stand`) only when it is
  genuinely embedded in a wall — it recorded a `face` (only a
  horizontal-tile hit records one, so floor and ceiling arrows never
  qualify) and the tile just past that face is still solid, re-checked
  every step. A shallow shot lying in the floor is walked over, and open
  the wall under a perch and the body drops off it. When it does hold,
  the feet pin to the arrow's band and vy is zeroed, but `p.gr` stays
  false — no coyote, no walk (the walk motor stands down), no wall-run
  trigger, no spirit recharge. The perch is something to stop a fall and
  nothing else: the exits are a jump (a buffered press launches a
  normal jump), the arrow's destruction, a shove, a rope attach, a
  winch capture or death. While perched the AIM is clamped to the 180
  degrees away from the wall the arrow sits in
  (`Util.clamp_aim_away`): the stick, the keyboard nudge and the
  entering angle all pass through — you cannot fire back into the wall
  you lean against.
- **The gun.** Laser riflemen drop their gun at their death spot
  (player-arrow kills); walking into a dropped one (or a placed `gun`
  object) collects ONE explosive shot (`p.guns`). The next normal-arrow
  firing launches the GUN itself as the projectile (kind "gun"): it
  flies an arrow's arc a touch heavier (`gun.speed_scale`), carries no
  key, and detonates on ANY contact through `Arrows.detonate_bomb` —
  the shared red boom ring and proximity-falloff shove exactly like the
  bomb arrow (the "red bang on contact"), and equally silent. Placeholder
  art: a dark slab with a red tip (pickup held/rendered in
  render/world.lua + render/player.lua).
- **Hitstop.** `ctx.freeze` counts world-steps the simulation hangs:
  `Game:step` sets `ctx.dt = 0` while it is positive (every integrator
  and timer scales with dt, so the whole world freezes mid-state; the
  render keeps drawing, input cadence and bow turning run in real
  time) — then resets. Named kicks: a player hit (`Player.hurt`),
  any player-arrow enemy kill (in `Arrows.step_one`). Cleared by
  death (`Player.die`) and level load.
- **Juice: dust, not shake.** Takeoff, landing and wall-leap all throw
  `Particles.dust` (grey footfall puffs, strength-scaled by fall speed),
  and `Particles.fire_puff` blows a small report along the aim on every
  bow release. None of it touches the camera — jumps, landings and
  detonations alike leave the frame exactly on its follow.
- **Post-fire deaf window.** `aiming.stick_ignore_frames` (12) now also
  covers HELD movement: the walk motor zeroes its push while
  `Input.stick_deaf > 0` (the alias `ignore_stick` maintains), so a held
  direction cannot lurch the body the step the bow releases — keyboard
  and stick both fall under the count.
- **The wall-run.** A tile flagged `runnable` (the checkered box; the
  tileset's property, packed as flag bit 4) marks a wall-run lane: a
  maximal horizontal band where both 8px rows of a 16px art row are
  runnable, at least two art tiles long (`World:runnable_band_line`
  scans it). Runnable tiles
  block nothing — players, enemies and arrows all pass through — so a
  body can only ride the lane via the run. The trigger (`Player.wallrun_check`,
  at the top of `Player.physics` each step) fires when the player's body
  centre sits inside one of the line's first two tiles from a pushed end
  (the outermost tile, or one in from it) while holding jump and pushing
  toward the line (right at the left end, left at the right end; right
  wins if both are held, like the walk motor) — and while no rope or
  winch owns the body. The run (`Player.wallrun_step`) replaces the whole
  movement pass: no gravity, no collision, `vy` pinned to zero, `x`
  advancing at `config.wallrun.speed` and the ride y easing onto the
  band's centre line over `settle_steps` (the smooth transition in and
  out; entry also clears the jump buffer/hold so a leftover jump can't
  fire mid-run). Releasing the pushed direction ends the run in a straight
  drop (`vx`/`vy` zeroed); solid terrain at the leading edge's next step
  (a closed door mid-band) does the same. Reaching the line's far end
  (the leading edge crossing into the last tile) ends the run with a
  standard, holdable jump when jump is still held — momentum rides in
  `vx` either way. Jump is never required to SUSTAIN the run: only the
  direction is, and re-holding jump + direction while still inside the
  catch zone (the line's first two tiles from the pushed end) re-engages.
  Rope attaching/detaching is suspended during the run
  (a winch capture mid-run hands the body over immediately), the aim
  system keeps working through it (the run scales with world time, so it
  slows with aiming), and the animation is a dedicated cycle
  (`Player.wallrun_state`, `config.wallrun.cycle_*`) mirroring the ground
  run's cadence — `sprite_base` points at the ground-run frames until
  wall-run art lands. New tests live in `tests/wallrun_test.lua`.
- **The spirit arrow.** The swap cycle's third arrow kind
  (`normal -> rope -> spirit`; the test menu's *special arrows
  hidden* toggle — default on — drops the bomb and spirit from the
  cycle entirely, so `Player.arrow_step` walks normal -> rope only and
  an equipped special falls back to normal), fired through `Arrows.fire`
  but handled by `src/spirit.lua` (`Spirit.fire`) — it is **not an
  arrow at all**: no quiver cost (no projectile exists; the fire
  bypasses `ents.arrows` entirely), no keys, no sticking, no
  platforms, no trajectory in the world. The release applies its whole
  effect at the player's centre in one shot:
  - **the burst** — a ghostly-blue spark jet streaming out along the
    aim direction (the force's exhaust, `Particles.spirit_burst`:
    chunky flecks in spirit blue alternating with white). Nothing
    travels and nothing flashes: the burst marks the force, no wave,
    no projectile, no boom.
  - **the fling** — the body is knocked along the **exact opposite of
    the aim direction** (`config.spirit.push[p.aim_power]` px/step,
    scaled by the analog tilt with the `spirit.min_force_scale` floor
    so a light tilt still flings): aim down and you launch skyward,
    aim at a wall and you fly away from it. The knock is ADDED to the
    body's velocity (it stacks with jump and swing momentum), ends a
    caught-mid-launch wall-run (when the knock points up), and rides
    the winch-throw grace window (`spirit.shove_grace`): movement
    input and the walk cap are ignored so the fling plays out
    untouched, ending early on landing. An attached rope is cut at
    fire time (mobility tool, like every shove the bow makes), with
    `rope_cd` blocking an instant re-grab.
  - **the second jump** — any upward fling (the aim below level) is a
    guaranteed full-jump rise THROUGH the current fall: the vertical
    knock is floored so the body launches at the player's jump speed
    (`player.jump_velocity`) plus the one gravity tick the first
    integration step pays (`physics.gravity`), whatever it was falling
    at — even at top fall speed the fling still arcs a whole jump's
    height above the fired point. A floor, not a ceiling: stronger
    intended flings (a hi-power down-cast, a running start) keep their
    edge over it, and a level or upward aim grants nothing extra (the
    fall carries; the fling is purely lateral then).
  - **the once-per-airtime charge** — `p.spirit_armed` (a plain bool,
    true at every spawn/respawn) is burned by a shot and refilled each
    physics step the player stands on solid ground (`p.gr`, set in
    `Player.physics`); a spent bow **clicks**: `Spirit.fire` returns
    before anything happens — no fling, no burst, no rope cut. A jump
    takes the charge airborne without spending it (landing is what
    refills), so the tool reads as one free boost between landings,
    not flight.
  - **the ghost** — while the spirit kind is equipped the player reads
    as a **ghostly blue silhouette** (`src/render/player.lua` layers a
    translucent overlay in `spirit.tint_colour` at `spirit.tint_alpha`
    over the sprite, the same masking the i-frame shield uses; the
    shield's red wins while an i-frame lasts so hits stay legible).
    While aiming the preview shows the fling instead of a trajectory: a
    short spirit-coloured trail opening along the exact opposite of the
    aim (the way the body is about to fly).

- **The bomb arrow.** The swap cycle's fourth kind
  (`normal -> rope -> spirit -> bomb`; hidden from the cycle like the
  spirit while the test menu's *special arrows hidden* toggle is on),
  a real arrow in every way
  (quiver slot, gravity arc, the aim preview — which rings the blast's
  catch radius at the predicted contact point) except keys (rope and
  bomb arrows never carry or pick up them: a blast must not eat a
  puzzle key) and sticking: terrain, sticky surfaces (which
  would bounce other arrows), enemies and closed doors all **detonate**
  it at the contact. A direct enemy hit kills the touched enemy (blood
  out both sides, instant) and then blasts — a bomb jump off an enemy.
  `Arrows.detonate_bomb` runs the blast: the shared boom flash
  (`ents.booms`, sized to `bomb_arrow.blast_radius`), the spark/poof
  burst, and a hard radial shove with **linear proximity falloff** from
  `bomb_arrow.push` at the centre down to its `min_push_scale` share at
  the rim — sticking the arrow close is rewarded with bigger launches:
  - the player is **never damaged by their own bomb**; the knock is
    ADDED to their velocity (it stacks with jump and swing momentum —
    the point of the tool) and rides the winch-throw grace window
    (`bomb_arrow.shove_grace`): movement input and the walk cap are
    ignored so the fling plays out untouched, ending early on landing.
    A dead-centre blast shoves straight up.
  - enemies are shoved along the radial, never killed by the blast
    itself (the direct hit is what kills).
  - enemy projectiles: rockets knocked off their heading (the homing
    re-curves them later), thrown bombs and darts knocked off course.
  Firing a bomb cuts an attached rope (mobility tool, like the
  spirit); the blast knocks a line loose too, with `rope_cd` blocking
  an instant re-grab. Rocket or thrown-bomb tip hits go through the
  enemy blast as with other arrows, the arrow consumed either way. A
   bomb arrow that touches nothing poofs silently — no blast.

## The moving blocks

Movers (`src/movers.lua`, scanned in `src/level.lua` from `mover` /
`mover_trigger` Tiled objects) are the ride puzzle device: a solid block
of 1..3 art tiles a way — explicit `tiles_w`/`tiles_h` (int art tiles)
properties win, otherwise the object's own placed size rounds to tiles;
both clamp to `config.mover.max_tiles` — that travels back and forth
along a tile-aligned line for the required `distance` tiles from its
rest position. The line's direction is EXPLICIT ONLY: the required
`dir` object property (up / down / left / right) — nothing about the
block's shape implies it, so a block of any footprint can run any way,
and a missing or misspelled `dir` skips the mover with a warning,
pausing `pause_steps` (30, one
second) at each end — the SAME pause both ends. Per-instance `speed`
(px per world-time step; default 1.0) and `pause` overrides ride the
object properties. INTEGER speeds are the smooth ones: the block then
advances a whole pixel every step, so the scroll is perfectly even on
the pixel canvas; fractional speeds beat instead (1.2 hops 2px every
5th step, which reads as stutter). A mover without a usable
`distance` is skipped with a warning. Level1's debug sandbox carries
the demo pair (`mover_auto`,
a 1x1 horizontal cycler, and `mover_lift`, a 1x2 vertical lift).

- **Two flavours.** The kind IS the behaviour: an auto `mover` cycles
  forever (rest -> go -> pause -> back -> pause -> on and on); a
  `mover_trigger` waits parked at rest until stood on or struck, runs
  the line, pauses at the far end and returns on its own to park at
  rest again.
- **Solidity.** The block owns its CURRENT box, PIXEL-EXACT: a moving
  block is an object in the world, not tile-aligned terrain — its face
  travels mid-tile, and tile-granular solidity would claim each
  half-covered edge tile whole, supporting bodies on edge pixels that
  shift with the block's travel (edge-standing that flickers bind/sever
  as tile alignment changes, and an edge-stander the ride could never
  see, which froze the block under them). Solid ground to bodies in
  `solid_at` (`World:mover_at` tests the exact px box; `skip_mover`
  lets the mover's own stall checks pass), RECESSED to arrows in
  `solid_for_arrow` (like the pusher: tips fly into the block and
  strike), and a bouncy surface in `sticky_at` (arrows never embed in
  a moving block — they would hang over the void between pauses).
  Landing uses
  `World:mover_stand_y` in `resolve_y`'s stand chain: bodies land on
  the block's FRACTIONAL top face (the exact surface they ride, not
  the block's top edge).
- **Riding is ground.** Only the player rides (enemies are left for
  their patrol logic). A block is solid ground to the body passes
  (`p.gr`, friction, the walk motor, jump buffering, coyote time all
  flow through `solid_at`/`resolve_y` unchanged), so a rider can walk,
  stop, and jump on a moving block exactly as on normal ground. The
  platform-specific bits: the ride binds while the rider's feet y sit
  in the top-face band (`ride_margin`, 8px up) and their FOOT SPAN
  still overlaps the block — the footing rule matches `resolve_y`'s
  two-corner stand, so hanging a toe over the edge holds and only
  walking FULLY off severs. After the block's advance the carry
  follows the rider RELATIVELY by the same delta (vertical lifts
  press/pull the rider with the face, horizontal ones drag them along,
  clamped out of walls beside the line), and the next physics pass
  re-lands their feet exactly on the face via `mover_stand_y` — a
  falling rider caught inside the band drifts down onto the face
  naturally instead of being yanked to it. A rider also NEVER collides
  with the block they stand on: `resolve_x` skips the ridden mover
  (obj.ride as the solid_at skip), because a moving face sits mid-tile
  and tile-granular solidity would otherwise read the half-covered top
  row as a wall under the rider's own feet — sticking them and
  tile-snapping them sideways off the platform the moment they tried
  to walk. Jumping or walking off
  severs the ride (`vy < 0`, or the body leaving the block), and the
  sever INHERITS the block's live velocity (`m.vel`) into `p.vx`:
  jumping straight up from a moving block drifts with it and lands
  back on it, the way ground inertia would. `p.ride` clears on
  respawn.
- **Triggers** fire only from rest. The player trigger is a fresh
  LANDING on the top face: the edge reads "feet on the block" for
  re-arm (only feet that LEFT the band arm it again) and "grounded on
  it" for the fire — a rider who never gets off keeps it parked, by
  design. The arrow trigger consumes any player arrow tip entering
  the block (recessed, pusher-style: a poof at the tip; bomb arrows
  detonate their own blast at the strike first, then the strike fires
  the run). Mid-trip strikes are eaten without re-triggering.
- **Stalls, no crush.** The block never advances into anything solid:
  terrain, closed doors, another mover's box, or a BODY (player or
  enemy) in its path all stall it for the step (the banked step is
  dropped — nothing teleports through the way when it clears; the
  bank never grows past one step's worth). Riders on the top face are
  exempt (they move WITH the block); a lowering lift parks flush on
  the floor instead of crushing whoever stands beneath. A stalled
  block resumes the moment the way clears.
- **Room gating and time.** Movers beyond the active room freeze
  exactly where they sit (like the springs), and everything scales by
  `ctx.dt`, so movers ride aiming's slow motion. Tests:
  `tests/mover_test.lua`.

## The pusher (updraft / outdraft)

The pusher family (`pusher_01`-style objects placed with the Class
`Updraft` or `Outdraft`; shared sprite art 86 in `twang.tsx`) is the
launcher puzzle device: a solid one-art-tile block standing on the ground
that you hop over — and that flings you skyward when you shoot it. The
kind IS the variant: the **updraft** launches everything over it
straight up, the **outdraft** drains a cone above it up-and-away.

- **Body** (`src/level.lua` scan, `src/world.lua` solidity): the device
  object owns its tile like a door does — always solid to bodies (you
  bump it walking, stand on its top, jump over it), and recessed to
  arrows (`solid_for_arrow` answers false) so a player arrow's tip flies
  INTO the block and strikes. Every variant shares the art-86 sprite
  (a per-variant tick overlay in `src/render/world.lua` shows the flow
  direction: vertical ticks for the updraft, a splayed fan for the
  outdraft).
- **Strike** (`Arrows.step_one`'s per-substep pusher check): the tip
  entering the device's tile consumes the arrow (a poof at the strike
  point, like the winch capture) and fires `Arrows.trigger_pusher`. A
  bomb arrow's tip also detonates its own blast at the strike point
  first, so the two forces stack. Enemy arrows never strike it (the
  spirit arrow fires no projectile at all). Repeatable: every strike
  fires the push again.
- **The push** (`Arrows.trigger_pusher` through the shared zone-driven
  `Arrows.shove`, also used by `detonate_bomb`): the flash ring sized to
  the variant's catch radius plus a
  spark burst, then a shove on everything the variant's catch zone
  accepts, at CONSTANT strength (a predictable launcher). The player's
  knock is ADDED to their velocity — it stacks with jump and swing
  momentum, the point of the tool — riding the shove-grace window so
  the walk cap cannot clamp it, knocking an attached rope line (or
  winch reel) loose and ending a mid-launch wall-run. Enemies are
  shoved along the flow and never killed by the push; rockets, thrown
  bombs and darts are knocked off course.
  - **Updraft zone**: a box over the device's 16px block plus
    `config.pusher.up.side` art tiles to either side (2: a 5-tile pad
    band), from the device's top edge up to `config.pusher.up.reach`
    (64px) above it; caught targets launch straight up no matter where
    they sit in the box. A legacy `pusher`-kind object defaults to
    this variant.
  - **Outdraft zone**: everything within `config.pusher.out.radius`
    (64px) of the device's block centre whose radial points
    inside the `config.pusher.out.cone` half-angle (45°) around
    straight up is shoved along the radial (up-and-away); anyone
    beside or below the device feels nothing.
  - Per-instance overrides ride the object properties: `push`,
    `reach`, `side` (updraft), `cone`, `radius` (outdraft) and
    `shove_grace` beat the config defaults. Tests:
    `tests/pusher_test.lua`.

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
  sampled every `enemies.sight_step` px and terrain (solid tiles)
  blocks vision. No x-ray vision.
- **Arrow senses** (`Enemies.arrow_spot`): a flying PLAYER arrow the
  enemy can see (in front, in range, clear sight) marks its position as
  the tracked spot — patrol switches to an investigate, an existing
  search follows the arrow's path. A LANDING arrow alerts every enemy
  within `enemies.arrow_alert_radius` (80px) with no sight needed (the
  thunk carries) through `Arrows.notify_arrow_contact`. Enemy darts are
  their own gunfire: they alert nobody. Arrows never trigger combat —
  the arrow spot only ever feeds investigate/chase.
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
  arrow slits excluded) or to the world's edge. **A
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
  (`solid_for_arrow` — just short of the wall, not inside it), or
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
  through) **bounces the grenade body instead of
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
   refill, void death) and the never-shaking frame (the camera sits on
   its pure follow through every arrow kind, gun shots, jumps and hard
   landings);    `tests/rope_test.lua` covers the rope arrow
   (attach + hang, pendulum swing bounds, detach-preserving-velocity,
   winching, max-range expiry, platform exemption, swap, anchor loss)
   and the arrow perch (rope arrows give no platform, only wall arrows
   catch a fall, a floor arrow is walked over, opening the wall drops
   the perch), `tests/arrows_test.lua` covers how an arrow reads once
   it has struck terrain (the tip buried `embed_px` inside a wall and
   under a floor, the recorded face unchanged so the perch still
   catches, the shaft drawn buckled on a full-power hit and straight on
   a soft one, and a struck enemy bleeding at the entry wound and again
   out of the far face along the shot), and the spirit arrow
   (opposite-of-aim flings — airborne, grounded
   and additive, the power/force scaling, the ghost tint window, the
   rope cut and the quiver bypass); `tests/bomb_arrow_test.lua` covers the bomb
   arrow (the swap cycle, contact detonation on terrain and sticky
   surfaces, the blast's enemy shove with out-of-radius sparing, the
   direct-hit kill plus blast, the additive proximity-falloff shove,
   the harmless self-blast, the grace window and rope cuts at fire and
   blast, rocket/bomb/dart knocks, the key-carry exclusion, and the
   silent blast ring against a shaking enemy rocket blast);
   `tests/results_test.lua` covers the completion flow (exit touch ->
   results, grade thresholds, best time/grade recording, results-panel
   inputs, next-level/replay flow, death counting):

```sh
luajit tests/enemies_test.lua
luajit tests/laser_test.lua
luajit tests/rocketeer_test.lua
luajit tests/bomber_test.lua
luajit tests/bomb_arrow_test.lua
luajit tests/aftermath_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
luajit tests/menu_test.lua
luajit tests/levelselect_test.lua
luajit tests/foreground_test.lua
luajit tests/rooms_test.lua
luajit tests/results_test.lua
luajit tests/checkpoints_test.lua
luajit tests/levels_test.lua
luajit tests/levels_flow_test.lua
luajit tests/mover_test.lua
```

`tests/legacy_main.lua` is the frozen pre-refactor monolith with a
test-only snapshot hook appended (inert in a real LÖVE run). It remains
available as a historical reference for the original simulation; as the
AI is deliberately overhauled, `trace_baseline.txt` (current code) is
the live regression gate.
