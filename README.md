# twang

An archer side-scroller: a LÖVE 11 port of the twang pico-8 cart. Native
480x320 pixel rendering (16x16 tiles and sprites), a 30hz fixed-timestep
simulation and a smooth camera. Levels are edited in Tiled (see
`docs/tiled-format.md`).

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
| aim angle & force (while aiming) | left/right | left stick (analog) |
| power (while aiming) | up/down | physical dpad up/down |
| cycle arrow type | c | X |
| test menu panel | m / tab | start |
| menu: select item | up/down | dpad up/down |
| menu: toggle item | c | X |
| menu: close | z / x | right bumper / A / B |
| results: next level | z / x | right bumper / A / B |
| results: replay level | c | X |
| level select: choose level | up/down | dpad / left stick |
| level select: play | z / x / c | right bumper / A / B / X |
| fullscreen | f11 | — |
| quit | escape | back |

The game opens on a **level select**: the v1 ladder (see
`config.levels`) — eight handcrafted levels, one new idea each:
**meadow** (walk/jump/keys), **battlements** (archers + the first
switch-shot gate), **the crossing** (the rope swing), **springside**
(spring vaults + phase tiles), **arrowslit** (laser snipers behind
arrow slits — they can't see you through them, your arrows fly
through), **winchyard** (rope arrows into winches zip you across the
voids), **the vault** (multi-group keys; a bomb ride up to a floating
key) and **the keep** (rocketeers, bombers, everything at once). All
levels play against a plain sky-blue backdrop — no level carries
backdrop sprites. The select also ends with **level 1 (debug)** — the
original workshop map, always unlocked and outside the ladder, kept as
the sandbox for testing gameplay changes (every enemy type, winches,
the full puzzle kit). Levels are gated on progress — a level opens once
the previous one is cleared (best time/grade recorded in the save
directory), with the test menu's *unlock all* row lifting the gate for
testing. Touching a level's **exit flag** clears it: the results panel
shows the run's time, deaths and grade (gold ≤ the level's `gold`
time, silver ≤ `par`, bronze for the rest), then continues to the next
level — the level select after the last one. Swap replays.

## Test menu

The panel (`m` / `tab` / `start`) doubles as a test menu with four
toggles and a level-select row. The game world pauses while it's open.

- **doors/keys/locks hidden** — every key, lock and door vanishes: they
  stop rendering, doors stop blocking (and stop bouncing arrows), keys
  can't be picked up and locks can't be triggered, and a carried key
  drops off. Toggling back restores every piece to its pre-toggle state
  (keys consumed before the toggle stay consumed).
- **invincibility** — arrows and melee touches can't hurt you (no
  hearts lost, no i-frames). Falling off the world still kills, so a
  test session can't get stuck.
- **enemies enabled** — off makes every enemy invisible and inert: they
  stop updating, their arrows vanish and archers drop back to patrol
  (they were previously toggled with the keyboard `e` key / pad `Y`,
  both now unmapped). Toggling back on re-enables them.
- **unlock all levels** — lifts the level select's progress gating so
  any level can be started without clearing the previous ones.
- **level select** — leaves play for the launch level select (the game
  world stays paused behind it), where any unlocked level in
  `config.levels` can be started fresh.

While aiming, the world runs in slow motion and the bow's trajectory is
previewed. The world keeps simulating (and rendering) at the steady
full framerate while aiming — it just moves at 1/N speed — so aiming
never freezes it into a slideshow. Power levels: `lo` / `md` / `hi`.
With a control stick the
shot's force is analog too: the stick's tilt — how far it sits from
zero, from the deadzone edge up to full deflection — scales the launch
speed between a quarter and the power level's full speed, so a light
push lobs a slow, heavily arcing arrow while full tilt keeps the
maximum. The preview arc shows exactly where the shot will land.

The window opens at 3x the native 480x320 view (1440x960) and is
resizable; fullscreen (F11) keeps your desktop resolution. The game
always blits at a whole-number scale, so pixels stay square and sharp —
in fullscreen the image is centred and letterboxed rather than
stretched. The window also re-fits itself automatically when dragged to
a monitor with a different resolution, so it stays crisp everywhere.

## Gameplay

- Reach the level's **exit flag** to clear it; the level clock ticks in
  the HUD (top-centre) and the run is graded on the results panel
  (time / deaths / grade, best saved per level).
- **Checkpoint flags** (green) become your respawn point when touched,
  so falls and deaths don't cost the whole level.
- Walk, jump (coyote time + jump buffering, and head-corner forgiveness
  that slides you around ledges you jumped beneath), and shoot arrows.
  The jump is deliberately snappy: a quick rise and a heavy pull back
  down (same apex, ~14% less airtime than the cart's floaty arc).
- **Wall-run** across lanes of checkered boxes: jump into either of the
  two end-most squares of a line of them while holding jump and pushing
  toward the line, and you're carried through the band at a constant
  clip. Release the stick and you stop and drop straight down; reach the
  far end holding jump and you leap off it, or keep your momentum and
  fall if you let go.
- **Impacts read as set pieces**: enemy arrows, rockets and grenades
  slamming into terrain throw scorched chunks off platforms, walls,
  ceilings and floors, a laser beam blasts grit off whatever stops it,
  and every detonation shakes the camera (harder for bigger booms).
  The carnage lingers, too: a laser's wall end keeps throwing sparks
  for a second or so, and blasts near terrain leave a burnt face
  crackling with embers under a column of rising black smoke — simple
  dots standing in for the burnt-wall art. Your own arrows stay
  deliberately small and quiet when they hit surfaces — no chunks, no
  shake: you're the calm one in the fight.
- Arrows stick into walls, bounce off sticky surfaces and closed doors
  (nothing is left embedded in a doorway once a switch opens it), and
  can be stood on when embedded in vertical walls.
- **Rope arrows** (press `c` to cycle): limited-range arrows that anchor a
  rope between you and wherever they stick. Swing pendulum-style — your
  speed carries into and out of the swing, left/right pumps it, and
  up/down reels the rope in/out. Press jump to let go and keep your
  momentum. Miss the wall and the arrow poofs at max range.
- **Shockwave pulses** (press `c` twice): harmless concussive waves.
  The pulse leaves your bow as a semicircular front — a cone of force
  opening along your aim, sweeping only what lies ahead of it. It
  bounces off any surface (the ricochet re-aims the cone), grows as it
  travels — the wider front is easier to connect with — and fizzles out
  after only a short distance. Whatever the front sweeps gets shoved
  hard away from it: enemies (never killed), thrown bombs and enemy
  darts knocked off course, homing rockets knocked away from their
  heading, and you on a bounce-back — fire down at the ground under
  your feet (or at any nearby wall) and the reflected front launches
  you. Firing also cuts any attached rope. Waves don't occupy the
  arrow quiver; two can be airborne at once.
- **Bomb arrows** (press `c` three times): gravity-arced arrows that
  detonate on ANY contact — terrain, sticky surfaces, closed doors,
  enemies. A direct enemy hit kills it, then the blast shoves
  everything in its radius along the radial, with proximity falloff —
  closest sticks give the biggest launches — and it never hurts you:
  fire at a nearby wall behind you to fling yourself forward, or at the
  ground under your feet for a bomb jump harder than a spring. The
  shove is additive (it stacks with jumps and swings) and plays out
  untouched for a moment (no walk-speed clamp), and the blast also
  shoves enemies and knocks rockets, bombs and darts off course. Firing
  cuts any attached rope. Bombs occupy the arrow quiver like normal
  arrows, never carry keys, and a miss poofs silently.
- **Pushers** are the launcher trick in device form: a solid one-tile
  block you hop over. Shoot it with any arrow and it shoves everything
  within 4 tiles directly away from its centre at full force — stand
  above it (or jump over it) and fire down into it to be thrown straight
  up. Every strike fires it again; a bomb arrow stacks its blast with
  the push.
- Carry keys to locks (personally, or by shooting them from an arrow)
  to open doors. Every arrow strike toggles a switch: its doors open
  while every switch of its group is on, and close otherwise; a strike
  also vaults whoever is standing on that group's springs. Only the
  level's phase switches (flagged in Tiled) flip the phase-platform
  tiles — each system reacts to its own switches alone. Spring switches
  pop back out once the spring resets, ready to be shot again.
- **Rooms**: a level may be split into camera-framed rooms (rectangles
  flagged `room` in Tiled — see `docs/tiled-format.md`). Crossing a
  border wipes the screen and re-frames the camera on the new room;
  only the room you're in simulates, so nothing acts on you from
  off-screen, and everything (keys, opened doors, switches) persists
  across rooms.
- **Archers hunt**: they spot you only in front of them, with clear line
  of sight and within range, and keep tracking your position the whole
  time you're visible. Once spotted they draw briefly (you'll see
  their ballistic arc, like your own) and release a volley of three
  arrows one after another. While you stay visible they keep firing on
  a quick, randomized cadence. Break their line of sight and they open
  cover fire — holding their ground and shooting blind at your last
  known spot for about three seconds — then come looking for where you
  were, even off their platform (though they refuse drops deeper than
  four tiles). Spot them spotting you and they're back in the fight
  instantly.
- **Laser riflemen hunt** the same way — spotted only in front, in
  range, with clear line of sight — but charge a shot you can read:
  a quick blinking red sight locks onto you, then a thick laser beam
  flashes out and stops dead at whatever it reaches — you included.
  Getting caught costs a full heart, with sparks spraying off the
  impact point. The whole flash is over in a few frames. Each charge
  holds three shots: the follow-ups come fast, re-tracking you between
  shots, and only a spent burst buys the full recharge. Lose their
  line of sight and they cover your last known position with blind
  shots before coming to look for you.
- **Rocketeers lob rockets**: the same senses and cover-fire loop, but
  the telegraph is a blip of red sparks above their head and the shot
  goes straight up — the rocket climbs a short way, hangs above the
  launcher for a beat (your window to shoot it down), then turns on a
  dime and homes in on your live position, arcing over walls to reach
  you even behind cover (cover is no protection). Getting caught in its
  blast costs a full heart, and any enemy caught in the blast dies
  with you — the launcher included if it fires under a low ceiling.
  Each charge holds two rockets: the follow-up comes fast, re-tracking
  you, and only a spent burst buys the full recharge.
- **Melee enemies charge**: touch one and it hurts, but now they also
  hunt — a spotted player is sprinted after, and when you break their
  line of sight they head for where you were last seen before giving
  up and resuming their patrol. Arrow tips kill them on contact.
- You have three hearts (drawn top-left): a melee touch or enemy arrow
  costs half a heart, a laser beam or rocket blast costs a full heart;
  hits spray blood
  opposite the impact and shroud you in a fading red silhouette while
  you're invulnerable (further
  hits are ignored until it lapses). Enemy arrows stop dead at you for
  a moment when they land.
  Heart slots show full, half-drained and empty sprites. Losing the last
  half-heart respawns you (dropping any unconsumed key). Falling off the
  world kills outright.
- Enemies patrol at most ~10 tiles from where they were placed in Tiled
  (see `config.enemies.roam_tiles`).
- Fall off the world and you respawn (dropping any unconsumed key).

## Code

See `docs/architecture.md` for the module map, data flow and the
simulation's quirks. The plan for turning this tech demo into a game
lives in `docs/gameplan.md`. All tuning constants live in
`src/config.lua`.

## Tests

A snapshot harness keeps the simulation honest, and a behaviour suite
covers the enemy AI:

```sh
luajit tests/run.lua main.lua /tmp/trace.txt
luajit tests/trace_diff.lua tests/trace_baseline.txt /tmp/trace.txt
luajit tests/enemies_test.lua
luajit tests/laser_test.lua
luajit tests/rocketeer_test.lua
luajit tests/bomber_test.lua
luajit tests/player_test.lua
luajit tests/rope_test.lua
luajit tests/interactables_test.lua
luajit tests/slowmo_test.lua
luajit tests/menu_test.lua
luajit tests/levelselect_test.lua
luajit tests/foreground_test.lua
luajit tests/rooms_test.lua
luajit tests/results_test.lua
luajit tests/checkpoints_test.lua
luajit tests/levels_test.lua
luajit tests/levels_flow_test.lua
luajit tests/winch_test.lua
luajit tests/bomb_arrow_test.lua
luajit tests/aftermath_test.lua
luajit tests/wallrun_test.lua
luajit tests/pusher_test.lua
```

The trace diff must be empty. After an *intentional* gameplay change,
rebase the baseline first (see docs/architecture.md). Requires LuaJIT
(headless; no LÖVE needed).

## Tools

- `tools/build_level.lua` — the v1 ladder's level DSL: emits the four
  Tiled maps (`luajit tools/build_level.lua`)
- `tools/render_map.py` — renders any Tiled map to a sprite-accurate PNG
  (`python3 tools/render_map.py maps/meadow.json /tmp/meadow.png`)
- `tools/p8_to_tiled.lua` — migrates the original pico-8 cart to a Tiled
  JSON map: `luajit tools/p8_to_tiled.lua ../twang.p8 maps/level1.json`
- `tools/import_kenney.py` — spritesheet asset import (builds the
  256x256 sheet, upscaling each 8x8 source tile 2x2)
- `tools/upscale_sheet.py` — one-shot 2x2 upscale of an existing 8x8-era
  spritesheet to the current 16x16 format
- `tools/migrate_maps_16px.py` — one-shot migration of 8x8-era Tiled
  maps to the current 16x16 tile size (applied to both maps; kept for
  reference)

## Repository

The original pico-8 cart lives one directory up (`../twang.p8`).
