# twang game plan

From tech demo to a shippable ~8-level game. The simulation layer is
done and tested (see `architecture.md`); what's missing is game
structure: a goal to reach, level flow, progression, and an end.
Everything below builds on the existing tech — no new systems are
assumed beyond the small ones called out.

## The pitch

A side-scrolling archer platformer: every level is a fortress of
keys, doors, switches and enemies. Reach the exit before your hearts
run out — fast, clean runs earn better grades. One new idea per level,
taught by layout, never by text.

## Game structure

- **Sequence of 8 handcrafted levels** (`config.levels`), each 2–4
  minutes, one contiguous Tiled map each, split into camera-framed
  rooms (existing tech) so each level reads as "the tower", "the
  vault", etc.
- **Goal object**: a new `kind = exit` entity (flag/door). Touching it
  ends the level. Without it there is no win condition — this is the
  single most important addition.
- **Level results**: on exit, record time, deaths and hearts kept,
  show a grade (par times authored per level in `config.levels`), save
  best time + grade per level (LÖVE save dir, tiny JSON).
- **Flow**: title / level select (exists) -> play -> results panel ->
  next level. The test menu stays as a debug panel, hidden behind a
  keybind, not part of game flow.
- **Checkpoints**: reuse the existing `spawn` entity as a checkpoint
  (touch to set respawn); death respawns at the last touched
  checkpoint instead of the level start, at the cost of one heart
  slot? (decide: no — deaths already cost a full refill cycle; keep
  deaths cheap, keep time as the pressure.)

### Level ladder (each level introduces one idea)

| # | working name | teaches / features |
|---|--------------|--------------------|
| 1 | meadow | walk, jump, bow; no enemies; a key->lock->exit |
| 2 | battlements | archers; sticky-wall arrow platforms; first switch |
| 3 | the crossing | rope arrows over a chasm; melee chasers below |
| 4 | springside | spring + switch vaults; phase tiles introduced |
| 5 | arrowslit | laser riflemen; `arrow_pass` slits as the counter |
| 6 | winchyard | winch throws + propel arrows; vertical level |
| 7 | the vault | keys carried by arrows, multi-group doors, laser + archer mix |
| 8 | the keep | rocketeers + bombers; everything combined; longest level |

farmhouse/level1/level2 stay in `config.levels` as workshop levels
(flagged `hidden` in the select) until level 4–5 exist.

## Milestones

### M0 — make it a game (the spine) — DONE
Everything else is decoration until this works end to end.

1. ~~`exit` entity: sprite, touch -> level complete~~ (flag art, tile
   172; touch-checked in `Game:step`)
2. results panel (time/deaths/grade) + next/replay/select input
3. per-level `gold`/`par` thresholds in `config.levels`; grades
4. best-time/grade persistence (`src/save.lua`, LÖVE save dir; no-op
   headless)
5. level clock HUD (top-centre) + death counting (wrapped `ctx.die`)
6. level select: saved grade + best time per row, locked until the
   previous level is cleared, unlock-all toggle in the test menu

**Done when**: you can play 1 -> 8 with placeholder levels, see
results, and quit the game feeling like you finished it.

### M1 — content pass A (levels 1–4)
- Build the four levels in Tiled using only existing entity kinds.
- Each introduces exactly one mechanic; enemy counts start at zero and
  grow. Teach by safe setups: first archer on flat ground facing away,
  etc.
- Checkpoint entities in levels 3+ (1–2 per level).
- Playtest for pacing: death should read as the player's fault within
  one second.

### M2 — content pass B (levels 5–8) + difficulty
- Remaining levels; enemy mixes (rocketeer needs open sky + a sightline
  for the launcher; bombers over pits; lasers in corridors).
- Tune `config.enemies` per level via the existing per-instance
  property override (object properties in Tiled) instead of global
  retunes.
- Par-time tuning against real playthroughs.

### M3 — juice & feel
- Exit fanfare (particles exist; add a short jingle if audio comes in)
- Screen shake on rocket blast (small camera offset in `Camera`)
- Room-wipe polish, results-panel animation
- Sound: this is the biggest missing sensory layer. Even a minimal
  pass — bow release, hit, door open, exit, rocket alarm — transforms
  it. (New dependency or hand-rolled sfx; decide in M3.)

### M4 — ship
- Title screen text on the level select; controls reminder on level 1
  only (the HUD hints already exist)
- Icon + window title polish
- Full test-suite green; rebase trace baseline after each gameplay
  change (M0 touches game flow, so expect one rebase there)
- README rewritten from "tech demo" to "game"

## Reuse map (what already covers what)

| Plan item | Existing tech |
|-----------|---------------|
| Levels, progression data | `config.levels`, `Game:load_level` |
| Checkpoints | `spawn` entity + rooms |
| Per-level enemy tuning | per-instance object property override |
| Gating/puzzles | key/lock/door groups, switches, phase tiles |
| Set pieces | springs, winch, phase platforms |
| Screen-by-screen feel | rooms + wipes |
| Regression safety | trace harness + behaviour suites |

## Genuinely new code (the short list)

1. ~~`exit` entity~~ — done (level.lua, game.lua, world render)
2. ~~results panel + game state `complete`~~ — `src/render/results.lua`
3. ~~save file + grades~~ — `src/save.lua`
4. ~~level timer + deaths~~ — HUD clock; `ctx.die` wrapper counts
5. optional: audio

That's the whole engine-side list — everything else is authoring in
Tiled and tuning in `config.lua`, which is exactly where this project
wants the effort to go.

## Open decisions

- Hearts refill on checkpoint or only on death? (lean: on death only;
  hearts are the time-pressure surrogate)
- Arrow ammo? The cart had none; adding it changes the whole feel.
  Lean: keep infinite for the 8-level game, revisit for a sequel.
- Audio: sfx-only first, music much later or never (pico-8 aesthetic
  tolerates silence; don't block shipping on it).
- Grades: settled in M0 — time-only (gold/par thresholds per level);
  deaths are displayed on the results panel but don't grade (respawns
  already cost time).
