-- Central tuning for the simulation, rendering and world layout.
-- Every gameplay-relevant constant lives here so systems stay clean.

local Config = {
  window = {
    title = "twang",
    identity = "twang",
    scale = 6,        -- windowed default: 6x the 240x160 view (1440x960)
    vsync = 1,
    fullscreen = false,       -- start windowed; fullscreen_key toggles live
    fullscreen_key = "f11",
    highdpi = true,           -- native-resolution framebuffer (crisp on Retina)
  },

  view = {
    width = 240,  -- native render width in pixels
    height = 160, -- native render height in pixels
  },

  sim = {
    rate = 30,              -- fixed simulation rate, Hz
    max_accumulator = 0.25, -- seconds; tab-through never produces a huge catchup
  },

  tile_size = 8,

  -- The Tiled map driving the level (see src/tiled.lua for the format).
  map_file = "maps/level1.json",

  camera = {
    follow = 0.15, -- fraction of the remaining distance per step
  },

  physics = {
    gravity = 0.28,
    max_fall_speed = 3,
  },

  player = {
    width = 4,
    height = 6,
    hearts = 3,               -- health cap, in whole hearts (drawn top-left)
    half_hearts_per_hit = 1,  -- damage per hit (melee touch, enemy arrow)
    invuln_steps = 45,        -- post-hit invulnerability steps (1.5s)
    walk_speed = 1.5,
    acceleration = 0.30,
    air_acceleration_scale = 0.6,
    deceleration = 0.24,
    air_deceleration_scale = 0.35,
    slippery_friction = 0.1,
    coyote_frames = 8,
    jump_buffer_frames = 8,
    jump_velocity = -3.2,
    jump_accel_initial = 1.8,
    jump_accel = 0.9,
    jump_hold_frames = 6,
    landing_frames = 6,
    run_cycle_steps = 6,
    run_cycle_frames = 4,
  },

  world = {
    void_margin = 32, -- pixels below the world bottom at which the player dies
  },

  aiming = {
    turn_rate = 0.007,          -- turns (0..1) per held step
    start_power = 2,
    min_power = 1,
    max_power = 3,
    slow_motion_steps = 12,     -- full physics runs once every N steps while aiming
    downward_sin_threshold = 0.5, -- aim angle p8sin past this counts as "aimed down"
  },

  arrows = {
    max_active = 3,
    speeds = { 4.5, 6.75, 9.0 }, -- launch speed per power level
    enemy_speed = 8.25,
    gravity = 0.2025,            -- arrow arc gravity
    colour = 10,                 -- PICO-8 palette index of the shaft
    lifetime = 300,              -- flight steps before expiring
    stuck_lifetime = 32000,      -- steps an embedded arrow persists
    max_bounces = 2,             -- surviving bounces off sticky surfaces...
    spin_out_frames = 12,        -- ...then the next bounce spins out and vanishes
    spin_out_speed = 0.45,       -- spin-out rotation, radians per step
    grab_cooldown = 8,           -- steps before the player can re-grab a key
    substep_pixels = 4,          -- collision sample spacing along the flight path
    preview_steps = 14,          -- aim trajectory preview dots
  },

  rope = {
    max_range = 56,            -- px an unattached rope arrow flies before expiring
    min_length = 8,            -- shortest allowed rope (px)
    max_length = 56,           -- longest allowed rope (px)
    winch_speed = 0.35,        -- px per step the rope reels in/out
    colour = 6,                -- PICO-8 palette index of the rope line
  },

  enemies = {
    width = 6,
    height = 8,
    melee_speed = 0.6,
    archer_speed = 0.4,
    air_drag = 0.85,          -- horizontal damping while airborne
    detect_distance = 80,     -- archer sight range (px)
    shoot_cooldown = 90,
    roam_tiles = 10,          -- max tiles an enemy patrols from its spawn point

    -- archer senses and shooting
    sight_step = 4,           -- px between samples along the vision ray
    aim_steps = 20,           -- preparation steps after spotting the player
                              -- (2/3 of the original 30-step draw)
    volley_count = 3,         -- arrows per volley
    volley_spread = 0.06,     -- radians between the volley's arrows
    volley_stagger = 8,       -- steps between the volley's arrows (one at a time)
    rapid_min = 20,           -- minimum wait between follow-up volleys (steps)
    rapid_extra = 20,         -- extra randomized wait on top of rapid_min
    max_drop_tiles = 4,       -- investigating archer won't step off deeper drops
    investigate_timeout = 240, -- max steps spent walking to the last known spot
    investigate_reach = 8,    -- px from the last known spot before giving up
  },

  springs = {
    launch_velocity = -6,
    extension_frames = 12,
    pad_height = 4,  -- solid band at the tile's bottom (px): the inactive
                     -- spring sprite only fills the tile's lower half, so
                     -- bodies stand on the pad instead of hovering
  },

  particles = {
    gravity = 0.06,          -- fall speed gained per step
    poof_count = 8,          -- key-release / death / arrow-expiry puff
    poof_colour = 10,
    poof_life = { 8, 15 },   -- lifetime steps, min/max
    blood_count = 10,        -- same as enemies.blood_particles
    blood_colour = 8,
    blood_life = { 10, 19 },
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
  },
}

return Config
