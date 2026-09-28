-- src/tiled.lua: load Tiled (mapeditor.org) JSON maps for twang.
--
-- Editing conventions (tile properties, entity objects, puzzle groups)
-- are documented in docs/tiled-format.md. In brief:
--
-- * 8x8 orthogonal map: the twang.tsx terrain tileset (32 columns of
--   8px cells over the untouched 256x256 spritesheet; firstgid 1 in
--   maps). Old 16px cell O became the four 8px sub-tiles at Tiled's
--   linear ids (O//16)*64 + (O%16)*2 + {0, 1, 32, 33} (TL, TR, BL, BR);
--   external tilesets are resolved from .tsx files next to the map
-- * maps that place sprite art (the characters/numbers cells) also
--   reference chars16.tsx, a 16x16 tileset at firstgid 1025:
--   art label = 96 + (gid - 1025). Cells 96-103 and 128-170 are
--   RESERVED there (135 exempt: the phase platform is real terrain);
--   the loader rejects their use in tile layers
-- * per-tile custom properties drive the game: solid, sticky,
--   friction, arrow_pass, runnable, oneway, phase (switch-flipped
--   platforms) and kind (entity role)
-- * entities (spawn/key/lock/door/archer/melee/switch/spring) live as
--   tile objects on Object Layers, anchored at their 16px art box
-- * any number of visible tile layers; layers named "background" /
--   "foreground" (case-insensitive) are purely visual backdrop/overlay
--   grids, every other visible layer merges into the terrain grid (later
--   layers win on nonzero tiles)
-- * plain rectangles with Class/kind "room" are camera-framed rooms
--   (see docs/tiled-format.md)
-- * if no tileset defines kind properties at all, the pico-8 cart
--   defaults below apply (sprite label ids), so migrated levels need
--   no manual setup

local json = require("lib.json")

local CHARS_BASE = 96  -- art label of chars16.tsx's local tile 0
local ART = 16         -- entity art cell (px): object anchors & hit boxes

-- pico-8 cart defaults (sprite label ids in the sheet), used when no
-- tileset defines the matching property
local DEFAULT_KINDS = {
  spawn = 63, key = 70, lock = 71, door = 72, archer = 112, melee = 116,
  laser = 138, rocketeer = 138, bomber = 138, switch = 171, spring = 16,
  spring_ext = 33,   winch = 133, exit = 172, checkpoint = 173,
  pusher = 86, updraft = 86, outdraft = 86,
  mover = 17, mover_trigger = 17, movertrigger = 17,
  gun = 138,  -- a placed gun pickup (same cell art as the ranged enemies)
}

local tiled = {
  DEFAULT_KINDS  = DEFAULT_KINDS,   -- exported for tools (kind -> label)
  ART            = ART,             -- exported for tools
  CHARS_BASE     = CHARS_BASE,      -- exported for tools
}

local function read_file(path)
  if love and love.filesystem and love.filesystem.read then
    local c = love.filesystem.read(path)
    if c then return c end
    error("tiled: cannot read map file '" .. path .. "'")
  end
  local f = io.open(path, "rb")
  if not f then error("tiled: cannot read map file '" .. path .. "'") end
  local c = f:read("*a")
  f:close()
  return c
end

local function xml_unescape(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
            :gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- minimal .tsx reader: header attributes, the image reference and the
-- per-tile custom properties; everything else in the file is ignored
local function parse_tsx(xml)
  local tsx = {}
  local head = xml:match("<tileset[^>]*>")
  if head then
    for k, v in head:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do tsx[k] = v end
    tsx.tilewidth = tonumber(tsx.tilewidth)
    tsx.tileheight = tonumber(tsx.tileheight)
    tsx.tilecount = tonumber(tsx.tilecount)
    tsx.columns = tonumber(tsx.columns)
    tsx.spacing = tonumber(tsx.spacing)
    tsx.margin = tonumber(tsx.margin)
  end
  local img = xml:match("<image[^>]*>")
  if img then
    local a = {}
    for k, v in img:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do a[k] = v end
    tsx.image = xml_unescape(a.source or "")
    tsx.imagewidth = tonumber(a.width)
    tsx.imageheight = tonumber(a.height)
  end
  tsx.tiles = {}
  -- a self-closing tile stub (`<tile id="86"/>`) would otherwise be
  -- paired with the NEXT record's closer, swallowing that tile's own
  -- properties (this ate the wall-run lane's runnable flag once); give
  -- stubs an empty body so they pair with themselves
  xml = xml:gsub('<tile%s+id="(%d+)"[^>]*/>', '<tile id="%1"></tile>')
  for id, body in xml:gmatch('<tile%s+id="(%d+)"%s*(.-)</tile>') do
    local props = {}
    for pm in body:gmatch("<property%s+(.-)/>") do
      local a = {}
      for k, v in pm:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do a[k] = v end
      if a.name then
        if a.type == "bool" then
          props[a.name] = (a.value == "true")
        elseif a.type == "int" or a.type == "float" then
          props[a.name] = tonumber(a.value)
        else
          props[a.name] = xml_unescape(a.value or "")
        end
      end
    end
    local n = tonumber(id)
    tsx.tiles[n + 1] = { id = n, properties = props }
  end
  return tsx
end

-- Tiled stores custom properties either as a name->value map (Lua export)
-- or as an array of {name=, type=, value=} records (JSON). normalize both.
local function prop_map(props)
  if type(props) ~= "table" then return {} end
  local first = props[1]
  if type(first) == "table" and first.name ~= nil then
    local m = {}
    for _, p in ipairs(props) do m[p.name] = p.value end
    return m
  end
  return props
end

-- Sprite labels reserved for chars16 (NOT terrain; 135 exempt: the
-- phase platform is a real tile).

-- The 16px art label of a terrain sub-tile id t (the sheet's 16-column
-- art row-major layout recovered from the tileset's 32-column 8px grid:
-- art col = (t % 32) // 2, art row = (t // 32) // 2).
local function sub_label(t)
  return math.floor((t % 32) / 2) + math.floor(t / 64) * 16
end
local function reserved_label(label)
  if label == 135 then return false end
  return (label >= 96 and label <= 103) or (label >= 128 and label <= 170)
end

function tiled.load(path)
  local m = json.decode(read_file(path))
  assert(m.type == "map", "tiled: not a Tiled map: " .. path)
  assert(not m.infinite, "tiled: infinite (chunked) maps are not supported")
  assert(m.tilewidth == 8 and m.tileheight == 8,
    "tiled: twang uses 8x8 tiles (got "
    .. tostring(m.tilewidth) .. "x" .. tostring(m.tileheight) .. ")")
  assert(m.orientation == "orthogonal",
    "tiled: only orthogonal maps are supported")

  -- tilesets: the 8px terrain tileset is required; the 16px sprite
  -- tileset (chars16) is optional and routed by firstgid
  assert(m.tilesets and #m.tilesets >= 1,
    "tiled: the map must reference the twang.tsx tileset")
  local terrain, chars
  for _, ref in ipairs(m.tilesets) do
    local ts = ref
    if ref.source then
      -- external tileset (.tsx next to the map)
      local dir = path:match("^(.-)[^/\\]*$") or ""
      ts = parse_tsx(read_file(dir .. ref.source))
      ts.firstgid = ref.firstgid
    end
    if ts.tilewidth == 8 and ts.tileheight == 8 then
      assert(not terrain, "tiled: two 8px terrain tilesets in " .. path)
      terrain = ts
    elseif ts.tilewidth == 16 and ts.tileheight == 16 then
      assert(not chars, "tiled: two 16px sprite tilesets in " .. path)
      chars = ts
    else
      error("tiled: unsupported tileset geometry "
        .. tostring(ts.tilewidth) .. "x" .. tostring(ts.tileheight)
        .. " in " .. path)
    end
  end
  assert(terrain, "tiled: no 8px terrain tileset in " .. path)
  assert(terrain.columns == 32,
    "tiled: the terrain tileset must be 32 columns of 8x8 spritesheet cells")
  local n_tiles = tonumber(terrain.tilecount)
    or (terrain.columns
        * math.floor((terrain.imageheight or 0) / terrain.tileheight))
  assert(n_tiles and n_tiles <= 1024,
    "tiled: the terrain tileset must cover the 256x256 spritesheet")
  if chars then
    assert(chars.columns == 16,
      "tiled: the sprite tileset must be 16 columns of 16x16 cells")
  end
  local chars_first = chars and chars.firstgid or math.huge

  -- per-tile flags/kinds from the terrain tileset's records, keyed by
  -- 8px sub-tile id; kinds resolve back to their 16px art label
  local gff = {}
  for i = 1, n_tiles do gff[i] = 0 end
  local kinds_by_sub, phase_by_sub = {}, {}
  -- (pairs: the tiles array is sparse -- one slot per local tile id)
  for _, tt in pairs(terrain.tiles or {}) do
    local t = tt.id
    if t >= 0 and t < n_tiles then
      local p = prop_map(tt.properties)
      if p.solid    then gff[t + 1] = gff[t + 1] + 1 end
      if p.sticky   then gff[t + 1] = gff[t + 1] + 2 end
      if p.friction then gff[t + 1] = gff[t + 1] + 4 end
      if p.arrow_pass then gff[t + 1] = gff[t + 1] + 8 end
      if p.runnable then gff[t + 1] = gff[t + 1] + 16 end
      if p.oneway   then gff[t + 1] = gff[t + 1] + 32 end
      if p.kind     then kinds_by_sub[t]  = p.kind end
      if p.phase    then phase_by_sub[t]  = true end
    end
  end

  -- kinds from the sprite tileset (chars16): label = CHARS_BASE + local
  local kinds_by_chars = {}
  if chars then
    for _, tt in pairs(chars.tiles or {}) do
      local t = tt.id
      local p = prop_map(tt.properties)
      if p.kind then kinds_by_chars[t] = p.kind end
    end
  end

  -- kinds: tileset wins, cart defaults fill the gaps (all label ids)
  local special = {}
  for name, id in pairs(DEFAULT_KINDS) do special[name] = id end
  for t, name in pairs(kinds_by_sub) do special[name] = sub_label(t) end
  for t, name in pairs(kinds_by_chars) do
    special[name] = CHARS_BASE + t
  end

  -- tile layers by role: named "background"/"foreground" (case-insensitive)
  -- are purely visual layers, kept out of the collision grid entirely --
  -- their tiles are often solid-flagged terrain art reused as scenery.
  -- Every other visible layer is gameplay terrain, merged into one grid
  -- (later layers win on nonzero tiles).
  local W, H = m.width, m.height
  local cells, bg_cells, fg_cells = {}, {}, {}
  local n_layers = 0
  local function merge(data, into)
    for i = 1, W * H do
      local gid = data[i] or 0
      if gid > 0 then
        if gid >= chars_first then
          print("tiled: warning - sprite art gid " .. gid
            .. " used in a terrain layer (reserved for object layers); "
            .. "ignored")
        else
          local t = gid - terrain.firstgid
          if t < 0 or t >= n_tiles then
            print("tiled: warning - GID " .. gid .. " is outside the "
              .. "terrain tileset (tile " .. tostring(t) .. "); ignored")
          else
            local label = sub_label(t)
            if reserved_label(label) then
              print("tiled: warning - terrain cell " .. t
                .. " is reserved sprite art (label " .. label .. "); ignored")
            elseif t > 0 then
              into[i] = t
            end
          end
        end
      end
    end
  end
  for _, layer in ipairs(m.layers or {}) do
    if layer.type == "tilelayer" and layer.visible ~= false then
      n_layers = n_layers + 1
      local data = layer.data
      assert(type(data) == "table",
        "tiled: tile layer '" .. tostring(layer.name) .. "' has no data")
      assert(layer.width == W and layer.height == H,
        "tiled: layer '" .. tostring(layer.name) .. "' size mismatch")
      local role = layer.name and layer.name:lower() or nil
      if     role == "background" then merge(data, bg_cells)
      elseif role == "foreground" then merge(data, fg_cells)
      else merge(data, cells) end
    end
  end
  assert(n_layers > 0, "tiled: map has no visible tile layers")

  -- object layers hold all entities: tile objects whose role comes from
  -- a kind property / the placed tile's kind / the Class field, grouped
  -- by name (with a "<kind>_" prefix stripped) or a "group" property
  local KIND_NAMES = {}
  for name in pairs(DEFAULT_KINDS) do KIND_NAMES[name] = true end
  local objects = {}
  local rooms = {}
  for _, layer in ipairs(m.layers or {}) do
    if layer.type == "objectgroup" then
      for _, o in ipairs(layer.objects or {}) do
        local p = prop_map(o.properties)
        -- rooms: plain rectangles with Class/kind "room" frame the
        -- camera (docs/tiled-format.md); they are not entities
        local oclass = ((o.type or o.class or ""):lower())
        if not o.gid and (oclass == "room" or p.kind == "room") then
          if (o.rotation or 0) % 360 ~= 0 then
            print("tiled: warning - room '" .. tostring(o.name)
              .. "' is rotated; rotation ignored")
          end
          local tw, th = terrain.tilewidth, terrain.tileheight
          local rx = math.floor((o.x or 0) / tw + 0.5) * tw
          local ry = math.floor((o.y or 0) / th + 0.5) * th
          local rw = math.max(tw,
            math.floor((o.width or 0) / tw + 0.5) * tw)
          local rh = math.max(th,
            math.floor((o.height or 0) / th + 0.5) * th)
          if o.x and o.x % tw ~= 0 or o.y and o.y % th ~= 0
          or o.width and o.width % tw ~= 0
          or o.height and o.height % th ~= 0 then
            print("tiled: warning - room '" .. tostring(o.name)
              .. "' is not tile-aligned; snapped to the tile grid")
          end
          rooms[#rooms + 1] = { name = o.name, x = rx, y = ry, w = rw, h = rh }
        else
          -- object art: sprite tileset by firstgid range, else the
          -- terrain tileset's sub-0 marker cell (floor(sub/4) = label)
          local gid = o.gid
          local label, kind
          if gid then
            if gid >= chars_first then
              local local_id = gid - chars_first
              label = CHARS_BASE + local_id
              kind = kinds_by_chars[local_id]
            else
              local sub = gid - terrain.firstgid
              label = (sub >= 0 and sub < n_tiles) and sub_label(sub)
                or nil
              kind = (sub >= 0 and sub < n_tiles) and kinds_by_sub[sub]
                or nil
            end
          end
          if not kind and o.type then
            -- Class field: "Door"/"Key"/... (case-insensitive)
            local tclass = o.type:lower()
            if KIND_NAMES[tclass] then kind = tclass end
          end
          if kind and KIND_NAMES[kind] then
            -- tile objects anchor at their bottom edge in Tiled; plain
            -- objects anchor at their top edge, except points, which mark
            -- the entity's feet (like a spawn marker). Entity art is the
            -- 16px cell (ART), identical to the 16px-era pipeline.
            local wx = o.x or 0
            local wy = o.y or 0
            -- Tiled rotates tile objects about their bottom-left anchor
            -- (degrees, clockwise on screen); work out the rotated bounding
            -- box so the entity occupies the cell the author sees in Tiled
            local rot = math.floor(((o.rotation or 0) % 360) / 90 + 0.5) * 90
            if gid then
              if rot ~= 0 then
                local rad = math.rad(rot)
                local cs, sn = math.cos(rad), math.sin(rad)
                local w = o.width or ART
                local h = o.height or ART
                local minx, miny = math.huge, math.huge
                for _, pt in ipairs({ {0,0}, {w,0}, {w,-h}, {0,-h} }) do
                  local rx = pt[1]*cs - pt[2]*sn
                  local ry = pt[1]*sn + pt[2]*cs
                  minx = math.min(minx, rx)
                  miny = math.min(miny, ry)
                end
                wx = wx + minx
                wy = wy + miny
              else
                wy = wy - (o.height or ART)
              end
            elseif o.width == nil and o.height == nil then
              wy = wy - ART  -- point objects: feet at the point
            end
            local g = p.group
            if g == nil and o.name and o.name ~= "" then
              local n = o.name
              if #n > #kind
              and n:lower():sub(1, #kind + 1) == kind .. "_" then
                g = n:sub(#kind + 2)      -- "key_01" -> group "01"
              elseif (kind == "updraft" or kind == "outdraft")
              and #n > 6 and n:lower():sub(1, 7) == "pusher_" then
                -- the pusher family shares the legacy "pusher_" name
                -- prefix, so variant-placed objects keep its grouping
                g = n:sub(8)              -- "pusher_01" -> group "01"
              else
                g = n
              end
            end
            local ent = {
              kind = kind, x = wx, y = wy, g = g, name = o.name,
              spr = label,
              rot = rot ~= 0 and rot or nil,
              -- the placed object's size rides along (tile objects are
              -- 16px art cells by default; a mover sizes its block
              -- footprint from the object's w/h, up to 3 art tiles a way)
              ow = o.width, oh = o.height,
            }
            -- pass other custom properties through for per-instance tuning
            -- (they override entity defaults in the game)
            for k, v in pairs(p) do
              if k ~= "kind" and k ~= "group" then ent[k] = v end
            end
            objects[#objects + 1] = ent
          else
            print("tiled: warning - object '" .. tostring(o.name)
              .. "' has no resolvable kind (no 'kind' property, its tile "
              .. tostring(gid and (gid - 1) or "nil")
              .. " has none, and its Class is not a kind); ignored")
          end
        end
      end
    end
  end

  -- room validation: warnings only (rooms are camera frames, not law).
  -- Uncovered map areas are "wilderness": whole-map clamping and
  -- everything simulates there.
  for i, room in ipairs(rooms) do room.i = i end
  if #rooms > 0 then
    local th = terrain.tileheight
    for a = 1, #rooms do
      for b = a + 1, #rooms do
        local ra, rb = rooms[a], rooms[b]
        if ra.x < rb.x + rb.w and rb.x < ra.x + ra.w
        and ra.y < rb.y + rb.h and rb.y < ra.y + ra.h then
          print("tiled: warning - rooms '" .. tostring(ra.name)
            .. "' and '" .. tostring(rb.name) .. "' overlap")
        end
      end
    end
    local covered = 0
    for _, room in ipairs(rooms) do covered = covered + room.w * room.h end
    if covered < W * H * terrain.tilewidth * th then
      print("tiled: note - rooms do not cover the whole map; uncovered "
        .. "areas clamp the camera to the whole map")
    end
  end

  -- serialize to the game's map format: four hex digits per 8px tile
  -- (16-bit tile ids; the 8px grid addresses 1024 sub-tiles), row-major
  local function hex_rows(grid)
    local rows = {}
    for r = 0, H - 1 do
      local buf = {}
      for c = 1, W do
        buf[c] = string.format("%04x", grid[(r) * W + c] or 0)
      end
      rows[r + 1] = table.concat(buf)
    end
    return rows
  end

  return {
    MAP_W = W,
    MAP_H = H,
    map   = hex_rows(cells), -- terrain grid (game's mget format)
    background = next(bg_cells) and hex_rows(bg_cells) or nil,
    foreground = next(fg_cells) and hex_rows(fg_cells) or nil,
    gff   = gff,           -- per-sub-tile flag bytes (bit0 solid, 1 sticky,
                           -- 2 friction, 3 arrow_pass, 4 runnable, 5 oneway)
    special = special,     -- kind name -> sprite label id
    phase_tiles = phase_by_sub, -- sub-tile ids flagged "phase"
    objects = objects,     -- entities placed as objects on object layers
    rooms = #rooms > 0 and rooms or nil, -- "room" rectangles (camera frames)
    map_layers = m.layers, -- raw layer list (tools/tests may inspect it)
    tileset_image = terrain.image,
  }
end

return tiled
