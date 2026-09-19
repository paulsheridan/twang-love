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
    rate = 30,              -- fixed simulation rate, Hz
    max_accumulator = 0.25, -- seconds; tab-through never produces a huge catchup
  },

  tile_size = 16,

  -- The Tiled map driving the level (see src/tiled.lua for the format).
  map_file = "maps/level1.json",

  camera = {
    follow = 0.15, -- fraction of the remaining distance per step
  },

  physics = {
    gravity = 0.56,
    fall_gravity_scale = 1.7, -- extra gravity while falling (vy > 0):
                              -- heavier descent, snappier end of jump
    max_fall_speed = 6,
  },

  player = {
    width = 8,
    height = 12,
    hearts = 3,               -- health cap, in whole hearts (drawn top-left)
    half_hearts_per_hit = 1,  -- damage per hit (melee touch, enemy arrow)
    invuln_steps = 45,        -- post-hit invulnerability steps (1.5s)
    walk_speed = 3,
    acceleration = 0.60,
    air_acceleration_scale = 0.6,
    deceleration = 0.48,
    air_deceleration_scale = 0.35,
    slippery_friction = 0.2,
    coyote_frames = 8,
    jump_buffer_frames = 8,
    jump_velocity = -6.4,
    jump_accel_initial = 3.6,
    jump_accel = 1.8,
    jump_hold_frames = 6,
    corner_nudge_px = 4,      -- head-corner clip: max slide around a ledge
    landing_frames = 6,
    run_cycle_steps = 6,
    run_cycle_frames = 4,
    -- i-frame feedback: a translucent red silhouette overlay that fades
    -- out over the last `shield_tint_fade_steps` of invulnerability
    -- (replaces the old blink, which hid the player during slow motion)
    shield_tint_colour = 8,   -- PICO-8 palette index (red)
    shield_tint_alpha = 0.55, -- peak overlay strength
    shield_tint_fade_steps = 15,
  },

  world = {
    void_margin = 64, -- pixels below the world bottom at which the player dies
  },

  aiming = {
    turn_rate = 0.007,          -- turns (0..1) per held step
    start_power = 2,
    min_power = 1,
    max_power = 3,
    slow_motion_steps = 12,     -- aiming divides world time by this: physics
                                -- runs every step with dt = 1/N (true slow
                                -- motion at a steady framerate)
    downward_sin_threshold = 0.5, -- aim angle p8sin past this counts as "aimed down"

    -- analog force: the stick's tilt (its distance from zero, remapped
    -- from the deadzone edge to full tilt, 0..1) scales the launch speed
    -- between min_force_scale and the power level's full speed
    force_deadzone = 0.3,     -- stick magnitude where force scaling starts
                              -- (matches input.lua's aim_stick deadzone)
    min_force_scale = 0.25,   -- launch speed scale at the deadzone edge
  },

  arrows = {
    max_active = 3,
    speeds = { 9, 13.5, 18 },  -- launch speed per power level
    enemy_speed = 16.5,
    gravity = 0.405,             -- arrow arc gravity
    colour = 10,                 -- PICO-8 palette index of the shaft
    lifetime = 300,              -- flight steps before expiring
    stuck_lifetime = 32000,      -- steps an embedded arrow persists
    max_bounces = 2,             -- surviving bounces off sticky surfaces...
    spin_out_frames = 12,        -- ...then the next bounce spins out and vanishes
    spin_out_speed = 0.45,       -- spin-out rotation, radians per step
    grab_cooldown = 8,           -- steps before the player can re-grab a key
    substep_pixels = 8,          -- collision sample spacing along the flight path
    player_stick_frames = 12,    -- steps an arrow rests at a player hit
                                 -- before vanishing (visible impact point)
    preview_steps = 14,          -- aim trajectory preview dots (each spans
                                 -- 2x the pixels at the doubled speeds, so the
                                 -- count stays put to keep the same arc)
  },

  keys = {
    pickup_pad = 6,  -- px grown around a key for forgiving pickup proximity
    lock_pad   = 8,  -- px grown around a lock for forgiving trigger proximity
  },

  rope = {
    max_range = 112,           -- px an unattached rope arrow flies before expiring
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
    stick_grace = 12,          -- steps after release that movement input stays ignored
                               -- (the throw's physics must play out untouched);
                               -- ends early once the player lands
    debug = false,             -- write winch_debug.txt trace lines (src/winchlog.lua)
  },

  enemies = {
    enabled = true,           -- global on/off toggle (controller Y / key e)
    width = 12,
    height = 16,
    melee_speed = 1.2,
    melee_chase_speed = 2.5,  -- sprint while a seen player is being chased
    archer_speed = 0.8,
    air_drag = 0.85,          -- horizontal damping while airborne
    detect_distance = 160,    -- archer sight range (px)
    shoot_cooldown = 90,
    roam_tiles = 10,          -- max tiles an enemy patrols from its spawn point

    -- archer senses and shooting
    sight_step = 8,           -- px between samples along the vision ray
    aim_steps = 10,           -- preparation steps after spotting the player
                              -- (1/3 of the original 30-step draw)
    volley_count = 3,         -- arrows per volley
    volley_spread = 0.06,     -- radians between the volley's arrows
    volley_stagger = 8,       -- steps between the volley's arrows (one at a time)
    rapid_min = 20,           -- minimum wait between follow-up volleys (steps)
    rapid_extra = 20,         -- extra randomized wait on top of rapid_min
    max_drop_tiles = 4,       -- investigating archer won't step off deeper drops
    investigate_timeout = 240, -- max steps spent walking to the last known spot
    investigate_reach = 16,   -- px from the last known spot before giving up

    -- laser rifleman (archer-like brain: see -> blink-aim -> beam ->
    -- wait/investigate); senses and patrol knobs above are shared
    laser_speed = 0.8,        -- patrol speed (px per step)
    laser_sight_steps = 18,   -- blinking-sight aim duration before firing
                              -- (0.6s: a quicker draw than the archer's)
    laser_sight_blink = 6,    -- sight blink cadence (steps per on/off toggle)
    laser_burst_count = 3,    -- shots per charge before the full recharge
    laser_burst_min = 12,     -- minimum wait between a burst's shots (steps)
    laser_burst_extra = 12,   -- extra randomized wait on top of laser_burst_min
    laser_beam_steps = 5,     -- steps the fired beam stays live: a brief
                              -- flash, over in a few frames
    laser_beam_width = 6,     -- beam thickness (px)
    laser_half_hearts = 2,    -- damage per beam hit (a full heart)
    laser_ray_step = 4,       -- px between samples along the beam's ray
    laser_rapid_min = 45,     -- minimum recharge wait after a burst (steps)
    laser_rapid_extra = 45,   -- extra randomized wait on top of laser_rapid_min

    -- rocketeer (archer-like brain: see -> blink-aim -> rocket -> wait/
    -- investigate); senses and patrol knobs above are shared. Rockets
    -- launch straight up from just above the head, climb to a hover
    -- point, hang there briefly, then turn on a dime toward the
    -- player's live position and hunt (behind cover too), detonating on
    -- proximity, terrain contact or age.
    rocketeer_speed = 0.8,    -- patrol speed (px per step)
    rocket_aim_steps = 18,    -- blinking-telegraph aim duration before firing
    rocket_sight_blink = 6,   -- telegraph blink cadence (steps per on/off)
    rocket_burst_count = 2,   -- rockets per charge before the full recharge
    rocket_burst_min = 15,    -- minimum wait between a burst's rockets (steps)
    rocket_burst_extra = 15,  -- extra randomized wait on top of rocket_burst_min
    rocket_rapid_min = 60,    -- minimum recharge wait after a burst (steps)
    rocket_rapid_extra = 60,  -- extra randomized wait on top of rocket_rapid_min
    rocket_speed = 4,         -- constant cruise speed once flying (px/step)
    rocket_turn_rate = 0.05,  -- max heading change toward the player (rad/step)
    rocket_hover_height = 24, -- px climbed above the launch before the hover
    rocket_hover_steps = 12,  -- steps it hangs before turning on a dime
    rocket_hit_w = 12,        -- rocket hitbox (px, around the centre) for
    rocket_hit_h = 12,        -- arrow-tip detonations: generous, a near
                              -- miss still counts as a hit
    rocket_proximity = 12,    -- px from the player's centre that trips the fuse
    rocket_blast_radius = 28, -- px damage radius of the explosion
    rocket_half_hearts = 2,   -- damage per blast hit (a full heart)
    rocket_lifetime = 150,    -- steps before an untriggered rocket detonates
    rocket_max_alive = 4,     -- rockets airborne at once (global cap)
    rocket_jitter = 0.1,      -- random launch heading offset (radians, each way)
    rocket_substep = 4,       -- px between fuse/terrain samples in flight
    rocket_trail_every = 2,   -- steps between smoke-trail puffs
    boom_frames = 8,          -- steps the explosion flash expands for
    suppress_steps = 90,      -- cover-fire window after losing sight (3s):
                              -- ranged enemies keep firing blind at the last
                              -- known position, then investigate
  },

  springs = {
    launch_velocity = -12,
    extension_frames = 12,
    pad_height = 8,  -- solid band at the tile's bottom (px): the inactive
                     -- spring sprite only fills the tile's lower half, so
                     -- bodies stand on the pad instead of hovering
  },

  phase = {
    alpha = 0.35,  -- draw alpha of phase tiles while they are non-solid
  },

  particles = {
    gravity = 0.12,          -- fall speed gained per step
    poof_count = 8,          -- key-release / death / arrow-expiry puff
    poof_colour = 10,
    poof_life = { 8, 15 },   -- lifetime steps, min/max
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
    spring_ext = 33,
    archer = 90,
    melee = 105,
    laser = 138,  -- aiming rifleman (kind also defined in maps/twang.tsx)
    rocketeer = 138,  -- rocket launcher (placeholder: shares the laser cell art)
    winch = 133,  -- small blue star
  },
}

return Config
