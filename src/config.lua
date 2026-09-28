-- Central tuning for the simulation, rendering and world layout.
-- Every gameplay-relevant constant lives here so systems stay clean.

local Config = {
  window = {
    title = "twang",
    identity = "twang",
    scale = 3,        -- windowed default: 3x the 480x320 view (1440x960)
    vsync = 1,
    fullscreen = false,       -- start windowed; fullscreen_key toggles live
    fullscreen_key = "f11",
    highdpi = true,           -- native-resolution framebuffer (crisp on Retina)
  },

  view = {
    width = 480,  -- native render width in pixels
    height = 320, -- native render height in pixels
  },

  sim = {
    rate = 60,              -- fixed simulation rate, Hz (world time is
                            -- measured in 30hz-steps: ctx.dt = 30/rate
                            -- per tick, so per-step constants are
                            -- rate-independent)
    max_accumulator = 0.25, -- seconds; tab-through never produces a huge catchup
  },

  tile_size = 8,

  -- The entity art cell (px): sprites, entity hit boxes and tile-count
  -- tunings stay anchored to the 16px art grid even though the terrain
  -- grid is 8px (the terrain tileset subdivides each art cell into four
  -- 8px sub-tiles; entity art never subdivides).
  art_size = 16,

  -- The Tiled map driving the level (see src/tiled.lua for the format).
  -- The headless harness boots this level; a real launch boots the
  -- level select's first entry (the intro level) instead.
  map_file = "maps/level1.json",

  -- Levels offered by the launch level select (Game:select_step).
  -- `file` is the Tiled JSON map, `name` the menu row. The first entry
  -- is the intro level a real launch opens on. `gold`/`par` are the
  -- grade thresholds in seconds (<= gold: gold, <= par: silver, else
  -- bronze — placeholders, retuned against real runs). Entries flagged
  -- `hidden` stay out of the level select (the workshop levels: the
  -- original cart's sandbox maps, kept for testing).
  levels = {
    -- the v1 ladder (docs/gameplan.md): one new idea per level
    { file = "maps/meadow.json",      name = "meadow",       gold = 50,  par = 120 },
    { file = "maps/battlements.json", name = "battlements",  gold = 80,  par = 180 },
    { file = "maps/crossing.json",    name = "the crossing", gold = 90,  par = 210 },
    { file = "maps/springside.json",  name = "springside",   gold = 110, par = 240 },
    { file = "maps/arrowslit.json",   name = "arrowslit",    gold = 130, par = 260 },
    { file = "maps/winchyard.json",   name = "winchyard",    gold = 150, par = 280 },
    { file = "maps/vault.json",       name = "the vault",    gold = 170, par = 300 },
    { file = "maps/keep.json",        name = "the keep",     gold = 200, par = 340 },
    { file = "maps/lv_forest.json",   name = "lv_forest",    gold = 240, par = 400 },
    -- workshop levels: level 1 is a visible debug row (always unlocked,
    -- outside the ladder's progression chain) — the sandboxes for testing
    -- gameplay changes; the rest stay fully hidden
    { file = "maps/level1.json",      name = "level 1",      gold = 90,  par = 180, debug = true },
    { file = "maps/rooms_demo.json",  name = "rooms demo",   gold = 45,  par = 120, debug = true },
    { file = "maps/farmhouse.json",   name = "farmhouse",    gold = 60,  par = 120, hidden = true },
    { file = "maps/level2.json",      name = "level 2",      gold = 90,  par = 180, hidden = true },
  },

  camera = {
    follow = 0.15, -- fraction of the remaining distance per world-step
                   -- (while the player rides a moving block, the camera
                   -- also feed-forwards their motion -- see src/camera.lua)
    shake_steps = 8, -- world-steps a detonation's shake decays over
    -- small "thud" shakes: jump/land/fire feedback — a short, tiny
    -- decaying offset distinct from the big blast shakes
    thud_steps = 3,   -- world-steps a thud decays over
    thud_jump = 1.5,  -- strength of a jump thud (px)
    thud_land = 3.0,  -- strength of a landing thud at full fall speed (px)
    thud_fire = 1.5,  -- strength of a bow-release thud (px)
    thud_gun = 2.5,   -- strength of a gun-fire thud (px, chunkier)
  },

  -- Rooms: camera-framed regions authored as "room" rectangles in the
  -- Tiled map (docs/tiled-format.md). A hysteresis-checked border
  -- crossing wipes the screen, re-frames the camera and switches which
  -- room's entities simulate.
  rooms = {
    fade_steps = 6,     -- wipe length in world-time steps (~0.2s):
                         -- half fading out, half in
    hysteresis_px = 4,   -- px the player's centre must sit inside a new
                         -- room before the switch fires
  },

  physics = {
    gravity = 0.72,
    fall_gravity_scale = 3.0, -- extra gravity while falling (vy > 0):
                              -- heavier descent, snappier end of jump
    max_fall_speed = 9,
  },

  player = {
    width = 8,
    height = 12,
    hearts = 3,               -- health cap, in whole hearts (drawn top-left)
    half_hearts_per_hit = 1,  -- damage per hit (melee touch, enemy arrow)
    invuln_steps = 45,        -- post-hit invulnerability world-steps (1.5s)
    walk_speed = 3,
    acceleration = 0.90,
    air_acceleration_scale = 0.7,
    deceleration = 0.90,
    air_deceleration_scale = 0.6,
    slippery_friction = 0.2,
    coyote_frames = 8,
    jump_buffer_frames = 8,
    -- Celeste-style jump: a near-instant launch, a short hold window
    -- (release early and the rise cuts in half), and a much heavier pull
    -- back down. Full hold rises ~3 tiles (was ~4); a tap hops less than
    -- one. The spirit's second-jump floor tracks jump_velocity, so the
    -- guaranteed rise shrinks with the arc. Frame counts are in
    -- world-time steps (30hz-steps), so they hold at any sim rate.
    jump_velocity = -6.6,
    jump_accel_initial = 5.0,
    jump_accel = 3.0,
    jump_hold_frames = 4,
    corner_nudge_px = 4,      -- head-corner clip: max slide around a ledge
    landing_frames = 6,
    run_cycle_steps = 6,
    run_cycle_frames = 4,
    -- wall slide (Celeste-style, no grab): while airborne and falling
    -- beside a wall the body presses itself against it and descends at
    -- slide_speed instead of free fall; pushing the direction AWAY from
    -- the wall releases the slide. Jumping while sliding launches a
    -- wall leap: up and away from the wall at walljump_push.
    slide_speed = 2.5,        -- px/world-step cap while wall sliding
    walljump_push = 3.2,      -- px/world-step away from the wall on a slide jump
    -- i-frame feedback: a translucent red silhouette overlay that fades
    -- out over the last `shield_tint_fade_steps` of invulnerability
    -- (replaces the old blink, which hid the player during slow motion)
    shield_tint_colour = 8,   -- PICO-8 palette index (red)
    shield_tint_alpha = 0.55, -- peak overlay strength
    shield_tint_fade_steps = 15,
    -- hitstop: world-time steps the simulation freezes when the player
    -- is hit (or kills an enemy) — a few frames of stuck-in-place impact
    freeze_steps = 3,
  },

  -- The wall-run: lines of "runnable" tiles (the checkered boxes; marked
  -- with the tileset's runnable property, pass-through to everything) are
  -- lanes the player traverses while airborne. Holding jump and pushing
  -- toward the line from one of its end tiles catches the player and
  -- carries them through the band at a constant speed; releasing the
  -- direction drops them straight down, and reaching the far end either
  -- jumps (jump still held) or keeps the momentum and falls. The ride y
  -- settles onto the band's centre line over settle_steps (the smooth
  -- transition in/out). The animation loop mirrors the ground run cycle;
  -- sprite_base points at the ground-run frames until wall-run art lands.
  wallrun = {
    speed = 3,          -- px/world-step along the wall (walk-speed feel)
    settle_steps = 4,   -- world-steps easing the body onto the band's centre
    cycle_steps = 6,   -- animation cadence, in world-time steps
    cycle_frames = 4,   -- animation frames
    sprite_base = 100,  -- first sprite index of the animation
  },

  world = {
    void_margin = 64, -- pixels below the world bottom at which the player dies
    -- the void behind everything: no level draws backdrop sprites any
    -- more (the Background tile layer is parsed but never rendered), so
    -- pits and open sky show this colour
    sky = { 0.529, 0.808, 0.922 },  -- sky blue (CSS skyblue)
  },

  aiming = {
    turn_rate = 0.0035,         -- turns (0..1) per held second of real
                                -- time: the bow turns in REAL time, so
                                -- this is rate-coupled (was 0.007/step
                                -- at 30hz)
    start_power = 2,
    min_power = 1,
    max_power = 3,
    slow_motion_steps = 12,     -- aiming divides world time by this: physics
                                -- runs every step with dt = (30/rate)/N
                                -- (true slow motion at a steady framerate)
    downward_sin_threshold = 0.5, -- aim angle p8sin past this counts as "aimed down"

    -- analog force: the stick's tilt (its distance from zero, remapped
    -- from the deadzone edge to full tilt, 0..1) scales the launch speed
    -- between min_force_scale and the power level's full speed
    force_deadzone = 0.3,     -- stick magnitude where force scaling starts
                              -- (matches input.lua's aim_stick deadzone)
    min_force_scale = 0.25,   -- launch speed scale at the deadzone edge
    -- after an arrow fires, the stick is deaf AND held movement keys
    -- are ignored for this many rendered frames (the walk motor reads
    -- the window too): the bow hand's aim deflection and any held
    -- direction must not lurch the body the step the bow releases
    stick_ignore_frames = 12,
  },

  arrows = {
    max_active = 8,
    speeds = { 9, 13.5, 18 },  -- launch speed per power level (px/world-step)
    enemy_speed = 16.5,
    gravity = 0.405,             -- arrow arc gravity
    colour = 10,                 -- PICO-8 palette index of the shaft
    lifetime = 300,              -- flight world-steps before expiring
    stuck_lifetime = 32000,      -- world-steps an embedded arrow persists
    max_bounces = 2,             -- surviving bounces off sticky surfaces...
    spin_out_frames = 12,        -- ...then the next bounce spins out and vanishes
    spin_out_speed = 0.45,       -- spin-out rotation, radians per world-step
    grab_cooldown = 8,          -- world-steps before the player can re-grab a key
    substep_pixels = 8,          -- collision sample spacing along the flight path
    player_stick_frames = 12,    -- world-steps an arrow rests at a player hit
                                 -- before vanishing (visible impact point)
    preview_steps = 14,          -- aim trajectory preview dots (each spans
                                 -- one world-step of flight, so the count
                                 -- stays put to keep the same arc)
  },

  -- The bomb arrow (the swap cycle's fourth kind): a gravity-arced
  -- arrow that detonates on ANY contact -- terrain, sticky surfaces,
  -- closed doors, enemies. A direct enemy hit kills the touched enemy
  -- (blood, instant) and then blasts; the blast itself is a point
  -- explosion that SHOVES everything in its radius -- the player
  -- (harmlessly, never damaged), other enemies, and enemy projectiles
  -- -- along the radial from the blast centre, with proximity falloff.
  -- The player's knock is additive (it stacks with jump and swing
  -- momentum, the point of the tool) and plays out untouched for
  -- shove_grace, like a winch throw, so the walk cap cannot eat it.
  bomb_arrow = {
    blast_radius   = 48,  -- px catch radius of the blast
    push           = 14,  -- shove impulse added at the blast's centre
                          -- (px/step); rises ~7 tiles, spring-tier
    min_push_scale = 0.5, -- push floor at the blast's rim: sticking the
                          -- arrow close is rewarded with bigger launches
    shove_grace    = 12,  -- world-steps the blast fling plays out untouched;
                          -- ends early once the player lands
  },

  -- The gun (late-game pickup): laser riflemen drop theirs when they
  -- die. Walking into the dropped gun collects it as ONE explosive
  -- shot: collecting it arms the bow, and the NEXT firing rides the
  -- gun itself as the projectile (an "gun arrow"): it flies like an
  -- arrow but detonates on ANY contact exactly like the bomb arrow's
  -- blast (ents.booms' red ring -- the "red bang" on contact -- the
  -- camera shake and the proximity-falloff shove ride along). One gun
  -- = one shot; normal physics otherwise. Placeholder art: the pickup
  -- draws as a chunky dark slab, the flying gun as a dark shell with a
  -- red tip.
  gun = {
    pickup_pad = 4,    -- px grown around the pickup for forgiving collection
    speed_scale = 0.85, -- launch speed scale vs the power level's arrow speed
                       -- (the gun is heavier than an arrow)
  },

  -- the bow's spirit arrow (the swap cycle's third arrow kind), a
  -- ghostly recoil-launch: firing it fires NO ARROW. The bow releases
  -- a burst of ghostly force at the player's centre -- a blue spark
  -- jet streaming out along the aim -- and the body is flung along the
  -- exact OPPOSITE of the aim direction: "any way you aim, you fly the
  -- other way". The impulse is ADDED to the body's velocity (it stacks
  -- with jump, swing and fall momentum, the point of the tool), plays
  -- out untouched for shove_grace steps so the walk cap cannot clamp
  -- it (ends early on landing), cuts an attached rope and ends a
  -- mid-launch wall-run. While the kind is equipped the player reads
  -- as a ghostly blue silhouette (tinted in src/render/player.lua).
  -- There is no projectile and no boom flash: the burst marks the
  -- force, nothing travels.
  --
  -- Two traversal rules ride on top: the fling carries a ONE-SHOT
  -- charge that only standing on solid ground refills (Player.physics
  -- sets spirit_armed; a spent bow clicks and does nothing), and any
  -- upward fling (aim below level) is a guaranteed SECOND JUMP -- it
  -- rises a full jump's height above the fired point even through a
  -- full-speed fall (Spirit.fire clamps the vertical knock to at least
  -- the jump's launch speed plus one gravity tick; stronger shots keep
  -- their edge).
  spirit = {
    push = { 10, 12.5, 15 }, -- fling impulse per power level (px/step;
                             -- hi rises ~10 tiles, above the bomb
                             -- blast's centre push of 14)
    shove_grace = 12,        -- world-steps the fling plays out untouched;
                             -- ends early once the player lands
    tint_colour = 12,        -- PICO-8 palette index of the ghost tint
    tint_alpha = 0.5,        -- strength of the equipped player's ghost
                             -- silhouette (a translucent sprite overlay)
    -- analog force floor: a light tilt still flings, but a spirit
    -- never crawls below this share of its push
    min_force_scale = 0.6,
  },

  keys = {
    pickup_pad = 6,  -- px grown around a key for forgiving pickup proximity
    lock_pad   = 8,  -- px grown around a lock for forgiving trigger proximity
  },

  exits = {
    touch_pad = 4, -- px grown around an exit for forgiving completion
  },

  checkpoints = {
    touch_pad = 6, -- px grown around a checkpoint flag for forgiving set
  },

  rope = {
    max_range = 132,           -- px an unattached rope arrow flies before expiring
    min_length = 16,           -- shortest allowed rope (px)
    max_length = 112,          -- longest allowed rope (px)
    winch_speed = 0.7,         -- px per step the rope reels in/out
    colour = 6,                -- PICO-8 palette index of the rope line
  },

  winch = {
    hit_pad = 2,               -- px grown around a winch's tile for the arrow tip capture
    reel_accel = 1.2,          -- px/step added to the reel speed each step (the "motor torque")
    max_reel_speed = 13,       -- pull-in speed cap (px per step)
    min_throw_speed = 10,      -- guaranteed release speed even after a soft entry (px per step)
    pass_radius = 10,          -- px from the winch centre at which the player releases
    stick_grace = 12,          -- world-steps after release that movement input stays ignored
                               -- (the throw's physics must play out untouched);
                               -- ends early once the player lands
    debug = false,             -- write winch_debug.txt trace lines (src/winchlog.lua)
  },

  -- The pusher (a puzzle device placed as an "updraft" or "outdraft"
  -- object): a solid one-tile block you hop over. A player arrow
  -- striking it is consumed (a poof, like the winch capture) and the
  -- device fires a variant-specific shove with a constant great-force
  -- impulse: the player's knock is ADDED to their velocity (it stacks
  -- with jump and swing momentum -- the point of the tool) and rides
  -- the grace window so the walk cap cannot clamp it; enemies are
  -- shoved along the flow, never killed; rockets, thrown bombs and
  -- darts are knocked off course. Repeatable: every strike fires it
  -- again. A bomb arrow striking it detonates its own blast and the
  -- device's push together (stacking).
  --
  --   updraft: a column drag -- everything overlapping the device's
  --   column (or `up.side` tiles to either side of it), between the
  --   device's top edge and `up.reach` px above it, is launched
  --   straight up.
  --   outdraft: a sector drain -- everything within `radius` of the
  --   device's tile centre whose radial lies inside the `out.cone`
  --   half-angle (from straight up) is shoved along the radial,
  --   up-and-away; anything beside or below the device feels nothing.
  pusher = {
    push = 18,         -- shove impulse everywhere in the catch zone
                       -- (px/step; stronger than the bomb arrow's 14:
                       -- rises ~14 tiles at full)
    shove_grace = 12,  -- world-steps the player's launch plays out untouched;
                       -- ends early once the player lands
    up = {
      side = 2,        -- art tiles either side of the device's column
                       -- the updraft still catches (the 5-tile pad band)
      reach = 64,      -- px above the device's top edge the column
                       -- drags (4 art tiles: fairly close, by design)
    },
    out = {
      cone = 45,       -- half-angle (degrees) of the sector above the
                       -- device that drains up-and-away (45 = quarter
                       -- sky: 90 degrees of the circle total)
      radius = 64,     -- px catch radius of the sector (4 tiles)
    },
  },

  -- Moving blocks: solid platforms placed as "mover" objects that travel
  -- back and forth along a tile-aligned line (the object's `distance`
  -- property, in tiles, along the object's rotated facing — a rotation
  -- of 180 points it left, 270 up). The block moves at `speed` px per
  -- world-time step and pauses `pause_steps` at each end of the line --
  -- same pause both ends (symmetric, predictable). Two flavours:
  --
  --   auto (kind "mover"): cycles forever, rest -> go -> pause -> back.
  --   trigger (kind "mover_trigger"): waits at rest until stood on (a
  --   rising edge: the player lands on its top, not one who never left)
  --   or a player arrow strikes it (the tip entering any tile of the
  --   block consumes the arrow, pusher-style), then runs to the far end,
  --   pauses and returns on its own.
  --
  -- Bodies standing on top ride the block (carried each step in
  -- src/movers.lua); anything in the path's way STALLS it rather than
  -- being crushed (no advancement that step, the block waits for the
  -- obstacle to clear). A trigger mover whose rider never got off stays
  -- parked until they do.
  mover = {
    speed = 1.0,        -- px per world-time step along the line. INTEGER
                        -- speeds move the block a whole pixel every
                        -- world-step (a perfectly even scroll on the
                        -- pixel canvas); fractional speeds beat instead
                        -- (1.2 hops 2px every 5th step, which reads as
                        -- stutter)
    pause_steps = 30,   -- wait at each end of the line (1s)
    max_tiles = 3,      -- footprint cap each way (art tiles, 16px, from
                        -- the object's width/height, clamped here)
    ride_margin = 8,    -- px the block's top face may travel out from
                        -- under a rider's feet before they are no
                        -- longer carried (riders trail slightly the
                        -- way a loose platform reads)
  },

  enemies = {
    enabled = true,           -- global on/off toggle (controller Y / key e)
    width = 12,
    height = 16,
    melee_speed = 1.2,
    melee_chase_speed = 2.5,  -- sprint while a seen player is being chased
    archer_speed = 0.8,
    air_drag = 0.85,          -- horizontal damping while airborne (per world-step)
    detect_distance = 160,    -- archer sight range (px)
    shoot_cooldown = 90,
    roam_tiles = 10,          -- max art tiles (16px) an enemy patrols
                              -- from its spawn point

    -- archer senses and shooting
    sight_step = 8,           -- px between samples along the vision ray
    aim_steps = 10,           -- preparation world-steps after spotting the
                              -- player (1/3 of the original 30-step draw)
    volley_count = 3,         -- arrows per volley
    volley_spread = 0.06,     -- radians between the volley's arrows
    volley_stagger = 8,      -- world-steps between the volley's arrows (one at a time)
    rapid_min = 20,           -- minimum wait between follow-up volleys (world-steps)
    rapid_extra = 20,         -- extra randomized wait on top of rapid_min
    max_drop_tiles = 4,       -- investigating archer won't step off drops
                              -- deeper than this (art tiles, 16px)
    investigate_timeout = 240, -- max world-steps spent walking to the last known spot
    investigate_reach = 16,   -- px from the last known spot before giving up

    -- laser rifleman (archer-like brain: see -> blink-aim -> beam ->
    -- wait/investigate); senses and patrol knobs above are shared
    laser_speed = 0.8,        -- patrol speed (px per world-step)
    laser_sight_steps = 18,   -- blinking-sight aim duration before firing
                              -- (0.6s: a quicker draw than the archer's)
    laser_sight_blink = 6,   -- sight blink cadence (world-steps per on/off toggle)
    laser_burst_count = 3,    -- shots per charge before the full recharge
    laser_burst_min = 12,     -- minimum wait between a burst's shots (world-steps)
    laser_burst_extra = 12,   -- extra randomized wait on top of laser_burst_min
    laser_beam_steps = 5,    -- world-steps the fired beam stays live: a brief
                              -- flash, over in a few frames
    laser_beam_width = 6,     -- beam thickness (px)
    laser_half_hearts = 2,    -- damage per beam hit (a full heart)
    laser_ray_step = 4,       -- px between samples along the beam's ray
    laser_rapid_min = 45,     -- minimum recharge wait after a burst (world-steps)
    laser_rapid_extra = 45,   -- extra randomized wait on top of laser_rapid_min

    -- rocketeer (archer-like brain: see -> blink-aim -> rocket -> wait/
    -- investigate); senses and patrol knobs above are shared. Rockets
    -- launch straight up from just above the head, climb to a hover
    -- point, hang there briefly, then turn on a dime toward the
    -- player's live position and hunt (behind cover too), detonating on
    -- proximity, terrain contact or age.
    rocketeer_speed = 0.8,    -- patrol speed (px per world-step)
    rocket_aim_steps = 18,    -- blinking-telegraph aim duration before firing
    rocket_sight_blink = 6,  -- telegraph blink cadence (world-steps per on/off)
    rocket_burst_count = 2,   -- rockets per charge before the full recharge
    rocket_burst_min = 15,    -- minimum wait between a burst's rockets (world-steps)
    rocket_burst_extra = 15,  -- extra randomized wait on top of rocket_burst_min
    rocket_rapid_min = 60,   -- minimum recharge wait after a burst (world-steps)
    rocket_rapid_extra = 60, -- extra randomized wait on top of rocket_rapid_min
    rocket_speed = 4,         -- constant cruise speed once flying (px/world-step)
    rocket_turn_rate = 0.05,  -- max heading change toward the player (rad/world-step)
    rocket_hover_height = 24, -- px climbed above the launch before the hover
    rocket_hover_steps = 12,  -- world-steps it hangs before turning on a dime
    rocket_hit_w = 12,        -- rocket hitbox (px, around the centre) for
    rocket_hit_h = 12,        -- arrow-tip detonations: generous, a near
                              -- miss still counts as a hit
    rocket_proximity = 12,    -- px from the player's centre that trips the fuse
    rocket_blast_radius = 28, -- px damage radius of the explosion
    rocket_half_hearts = 2,   -- damage per blast hit (a full heart)
    rocket_lifetime = 150,    -- world-steps before an untriggered rocket detonates
    rocket_max_alive = 4,     -- rockets airborne at once (global cap)
    rocket_jitter = 0.1,      -- random launch heading offset (radians, each way)
    rocket_substep = 4,       -- px between fuse/terrain samples in flight
    rocket_trail_every = 2,   -- world-steps between smoke-trail puffs
    boom_frames = 8,         -- world-steps the explosion flash expands for

    -- bomber (archer-like brain: see -> blink-aim -> thrown bomb ->
    -- wait/investigate); senses and patrol knobs above are shared. The
    -- throw flies in a straight line at the player's live centre; the
    -- bomber sets the bomb's fuse to a cheap, deliberately rough guess
    -- (straight-line distance over throw speed, jittered by
    -- bomb_fuse_error) instead of solving the shot exactly. In flight a
    -- bomb bursts like flak around an airborne player (proximity fuse)
    -- and like a grenade over one on the ground (pure timer, bounces
    -- off terrain, damped); a player arrow detonates it either way.
    bomber_speed = 0.8,       -- patrol speed (px per world-step)
    bomber_aim_steps = 18,    -- blinking-telegraph aim duration before throwing
    bomber_sight_blink = 6,  -- telegraph blink cadence (world-steps per on/off)
    bomber_burst_count = 2,   -- bombs per charge before the full recharge
    bomber_burst_min = 15,    -- minimum wait between a burst's bombs (world-steps)
    bomber_burst_extra = 15,  -- extra randomized wait on top of bomber_burst_min
    bomber_rapid_min = 60,   -- minimum recharge wait after a burst (world-steps)
    bomber_rapid_extra = 60, -- extra randomized wait on top of bomber_rapid_min
    bomb_speed = 3.5,         -- straight-line flight speed (px per world-step)
    bomb_fuse_error = 8,     -- ± world-steps of jitter on the crude fuse estimate
    bomb_flak_proximity = 14, -- px from an airborne player's centre that
                              -- bursts the bomb early (flak air-burst)
    bomb_blast_radius = 24,   -- px damage radius of the explosion
    bomb_half_hearts = 2,     -- damage per blast hit (a full heart)
    bomb_hit_w = 12,          -- bomb hitbox (px, around the centre) for
    bomb_hit_h = 12,          -- arrow-tip detonations: generous, like a rocket
    bomb_bounce_damp = 0.5,   -- speed kept per grenade bounce off terrain
    bomb_rest_speed = 0.5,    -- damped below this: the bomb rests where it
                              -- lies and burns its fuse out
    bomb_max_alive = 4,       -- bombs airborne at once (global cap)
    bomb_substep = 4,         -- px between fuse/terrain samples in flight
    suppress_steps = 90,     -- cover-fire window after losing sight (3s):
                              -- ranged enemies keep firing blind at the last
                              -- known position, then investigate
    -- arrow alert (new: enemies read arrows as noise): a player arrow
    -- FLYING past within detect_distance and clear sight marks the
    -- arrow's trail head as a last-known spot (patrol -> investigate,
    -- melee -> chase); one that LANDS alerts every enemy within
    -- arrow_alert_radius px regardless of sight — they heard the thunk
    arrow_alert_radius = 80,
  },

  springs = {
    launch_velocity = -12,
    extension_frames = 12,
    pad_height = 8,  -- solid band at the spring block's bottom (px): the
                     -- inactive sprite fills the block's lower half, so
                     -- bodies stand on the pad instead of hovering
  },

  phase = {
    alpha = 0.35,  -- draw alpha of phase tiles while they are non-solid
  },

  -- The visual "Foreground" Tiled layer (buildings / hidden spaces).
  -- While the player walks behind any of it the whole layer fades to
  -- invisible so their avatar stays readable, then eases back once
  -- they step out.
  foreground = {
    fade_margin_px = 6,    -- px grown around the player's box: touching
                           -- any overlay tile starts the fade
    fade_alpha_step = 0.125, -- alpha closed per world-time step (30hz):
                             -- a full fade either way in 8 steps (~0.27s)
  },

  particles = {
    gravity = 0.12,          -- fall speed gained per world-step
    poof_count = 8,          -- key-release / death / arrow-expiry puff
    poof_colour = 10,
    poof_life = { 8, 15 },  -- lifetime world-steps, min/max
    blood_count = 10,        -- same as enemies.blood_particles
    blood_colour = 8,
    blood_life = { 10, 19 },
    spark_count = 6,         -- laser-beam impact flecks on a player hit
    spark_colour = 10,
    spark_life = { 5, 10 },
    smoke_count = 1,         -- puffs per rocket trail emission
    smoke_colour = 5,
    smoke_life = { 6, 12 },
    boom_count = 12,         -- explosion spark flecks (alternates red/orange)
    boom_colour = 8,
    boom_life = { 6, 14 },
    -- chunky debris for a heavy player hit (laser beam, rocket or
    -- grenade blast): slabs of the player's kit tearing off, chunkier
    -- and longer-lived than the blood spray, in a metal-and-cloth mix
    shard_count = 9,
    shard_colours = { 5, 6, 7, 9 },
    shard_life = { 12, 24 },
    -- scorched chunks knocked off LEVEL GEOMETRY when an enemy
    -- projectile (arrow, rocket, grenade) or a laser beam slams into
    -- terrain: dark grit with a few embers riding along. The player's
    -- own arrows deliberately stay quiet when they hit surfaces --
    -- their hits are gentle, not set pieces
    scorch_count = 10,
    scorch_colours = { 5, 5, 6, 9, 2 },
    scorch_life = { 14, 28 },
    -- the spirit arrow's fire jet: chunky ghostly-blue flecks streaming
    -- out along the aim direction (the force's exhaust) with white core
    -- flecks alternating in, chunkier than sparks so the burst reads
    spirit_count = 14,
    spirit_colour = 12,      -- PICO-8 palette index (light blue)
    spirit_speed = 4,        -- max exhaust speed (px/world-step)
    spirit_life = { 8, 16 },
    -- impact aftermath: a laser's wall end or a blast close to terrain
    -- anchors a short-lived burning spot that keeps spitting sparks off
    -- the burnt surface for a second or so -- and, for blasts, black
    -- smoke drifting up. Stand-ins for the burnt-wall art to come.
    aftermath_steps = 40,      -- world-steps a burning spot lives (~1.3s)
    after_spark_every = 5,    -- world-steps between spark flecks (plus 0-3)
    after_spark_life = { 5, 11 },
    after_smoke_every = 7,    -- world-steps between smoke puffs (plus 0-4)
    after_smoke_life = { 24, 42 },
    after_smoke_g = 0.02,      -- smoke rises: near-zero gravity
    -- landing/jump dust: little grey footfall puffs at the feet, on
    -- jump takeoff and landings (harder falls kick more dust)
    dust_count = 5,
    dust_colour = 6,
    dust_life = { 6, 12 },
    -- the bow's release: a tiny poof fired along the aim (the shot's
    -- report), darker than the white key poof
    fire_count = 4,
    fire_colour = 6,
    fire_life = { 4, 9 },
  },

  -- PICO-8 cart fallbacks for special tiles; a Tiled tileset that defines
  -- "kind" properties overrides these per level (src/level.lua applies it).
  -- Note: the spawn marker scan in the tile layer always uses spawn_tile
  -- (a carried-over pico-8 cart wart, preserved deliberately).
  tiles = {
    spawn = 63,
    key = 70,
    lock = 71,
    door = 72,
    switch = 171,
    spring = 16,
    spring_ext = 32,  -- the extended spring's art (art cell 32)
    archer = 90,
    melee = 105,
    laser = 138,  -- aiming rifleman (kind also defined in maps/twang.tsx)
    rocketeer = 138,  -- rocket launcher (placeholder: shares the laser cell art)
    bomber = 138,  -- explosive thrower (placeholder: shares the laser cell art)
    winch = 133,  -- small blue star
    pusher = 86,  -- arrow-struck push pad (updraft launches straight up,
                  -- outdraft drains a cone above it up-and-away)
    mover = 17,   -- plain orange block (the crate movers draw with)
    exit = 172,   -- the level's exit flag (touching it clears the level)
    checkpoint = 173,  -- green checkpoint flag (touch sets the respawn)
  },
}

return Config
