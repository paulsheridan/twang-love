-- src/tiled.lua: load Tiled (mapeditor.org) JSON maps for twang.
--
-- Editing conventions (tile properties, entity objects, puzzle groups,
-- slope shapes) are documented in docs/tiled-format.md. In brief:
--
-- * 8x8 orthogonal map, the twang.tsx tileset (16 columns, firstgid 1);
--   external tilesets are resolved from .tsx files next to the map
-- * per-tile custom properties drive the game: solid, sticky, friction,
--   arrow_pass, kind (entity role) and slope (collision shape)
-- * entities (spawn/key/lock/door/archer/melee/switch/spring) live as
--   tile objects on Object Layers
-- * any number of visible tile layers; later layers win on nonzero tiles
-- * if the tileset defines no kind/slope properties at all, the pico-8
--   cart defaults below apply, so migrated levels need no manual setup

local json = require("lib.json")

-- pico-8 cart defaults (tile ids in the spritesheet), used when the
-- tileset does not define the matching property
local DEFAULT_KINDS = {
  spawn = 63, key = 70, lock = 71, door = 72, archer = 112, melee = 116,
  switch = 171, spring = 16, spring_ext = 33,
}
local DEFAULT_SLOPES = {
  [6] = "/floor",  [13] = "/floor", -- / floor
  [7] = "\\floor", [14] = "\\floor",-- \ floor
  [54] = "\\ceil", [61] = "\\ceil", -- \ ceiling
  [55] = "/ceil",  [62] = "/ceil",  -- / ceiling
}
local SLOPE_IDS = {
  ["/floor"] = 1, ["\\floor"] = 2, ["\\ceil"] = 3, ["/ceil"] = 4,
}

local tiled = {
  DEFAULT_KINDS  = DEFAULT_KINDS,   -- exported for tools (kind -> tile id)
  DEFAULT_SLOPES = DEFAULT_SLOPES,  -- exported for tools (tile id -> shape)
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

function tiled.load(path)
  local m = json.decode(read_file(path))
  assert(m.type == "map", "tiled: not a Tiled map: " .. path)
  assert(not m.infinite, "tiled: infinite (chunked) maps are not supported")
  assert(m.tilewidth == 8 and m.tileheight == 8,
    "tiled: twang uses 8x8 tiles (got "
    .. tostring(m.tilewidth) .. "x" .. tostring(m.tileheight) .. ")")
  assert(m.orientation == "orthogonal",
    "tiled: only orthogonal maps are supported")

  assert(m.tilesets and #m.tilesets == 1,
    "tiled: the map must have exactly one tileset")
  local ref = m.tilesets[1]
  local ts = ref
  if ref.source then
    -- external tileset (.tsx next to the map)
    local dir = path:match("^(.-)[^/\\]*$") or ""
    ts = parse_tsx(read_file(dir .. ref.source))
    ts.firstgid = ref.firstgid
  end
  assert(ts.columns == 16 and ts.tilewidth == 8 and ts.tileheight == 8,
    "tiled: tileset must be the 16-column 8x8 spritesheet.png")
  local n_tiles = tonumber(ts.tilecount)
    or (ts.columns * math.floor((ts.imageheight or 0) / ts.tileheight))
  assert(n_tiles and n_tiles <= 256,
    "tiled: too many tiles; the map format stores one tile per byte")

  -- per-tile flags/kinds/slopes from the tileset's custom properties
  local gff = {}
  for i = 1, n_tiles do gff[i] = 0 end
  local kinds_by_tile, slopes_by_tile = {}, {}
  local phase_by_tile = {}
  -- (pairs: the tiles array is sparse -- one slot per local tile id)
  for _, tt in pairs(ts.tiles or {}) do
    local t = tt.id
    if t >= 0 and t < n_tiles then
      local p = prop_map(tt.properties)
      if p.solid    then gff[t + 1] = gff[t + 1] + 1 end
      if p.sticky   then gff[t + 1] = gff[t + 1] + 2 end
      if p.friction then gff[t + 1] = gff[t + 1] + 4 end
      if p.arrow_pass then gff[t + 1] = gff[t + 1] + 8 end
      if p.kind     then kinds_by_tile[t]  = p.kind end
      if p.slope    then slopes_by_tile[t] = p.slope end
      if p.phase    then phase_by_tile[t]  = true end
    end
  end

  -- kinds: tileset wins, cart defaults fill the gaps
  local special = {}
  for name, id in pairs(DEFAULT_KINDS) do special[name] = id end
  for t, name in pairs(kinds_by_tile) do special[name] = t end

  -- slopes: if the tileset defines any, it defines them all
  local slope_type = {}
  if next(slopes_by_tile) then
    for t, s in pairs(slopes_by_tile) do
      local st = SLOPE_IDS[s]
      assert(st, "tiled: unknown slope shape '" .. tostring(s) .. "'")
      slope_type[t] = st
    end
  else
    for t, s in pairs(DEFAULT_SLOPES) do slope_type[t] = SLOPE_IDS[s] end
  end

  -- merge visible tile layers into one grid (later layers win on nonzero)
  local W, H = m.width, m.height
  local cells = {}
  local n_layers = 0
  for _, layer in ipairs(m.layers or {}) do
    if layer.type == "tilelayer" and layer.visible ~= false then
      n_layers = n_layers + 1
      local data = layer.data
      assert(type(data) == "table",
        "tiled: tile layer '" .. tostring(layer.name) .. "' has no data")
      assert(layer.width == W and layer.height == H,
        "tiled: layer '" .. tostring(layer.name) .. "' size mismatch")
      for i = 1, W * H do
        local gid = data[i] or 0
        if gid > 0 then
          local t = gid - ts.firstgid
          if t < 0 or t >= n_tiles then
            print("tiled: warning - GID " .. gid .. " is outside the "
              .. "tileset (tile " .. tostring(t) .. "); ignored")
            t = 0
          end
          if t > 0 then cells[i] = t end
        end
      end
    end
  end
  assert(n_layers > 0, "tiled: map has no visible tile layers")

  -- object layers hold all entities: tile objects whose role comes from
  -- a kind property / the placed tile's kind / the Class field, grouped
  -- by name (with a "<kind>_" prefix stripped) or a "group" property
  local KIND_NAMES = {}
  for name in pairs(DEFAULT_KINDS) do KIND_NAMES[name] = true end
  local kind_by_tile = {}
  for t, k in pairs(kinds_by_tile) do kind_by_tile[t] = k end
  local objects = {}
  local skipped_kinds = {}
  for _, layer in ipairs(m.layers or {}) do
    if layer.type == "objectgroup" then
      for _, o in ipairs(layer.objects or {}) do
        local p = prop_map(o.properties)
        local t = o.gid and (o.gid - ts.firstgid) or nil
        local kind = p.kind
          or (t and t >= 0 and t < n_tiles and kind_by_tile[t]) or nil
        if not kind and o.type then
          -- Class field: "Door"/"Key"/... (case-insensitive)
          local tclass = o.type:lower()
          if KIND_NAMES[tclass] then kind = tclass end
        end
        if kind and KIND_NAMES[kind] then
          -- tile objects anchor at their bottom edge in Tiled; plain
          -- objects anchor at their top edge, except points, which mark
          -- the entity's feet (like a spawn marker)
          local wx = o.x or 0
          local wy = o.y or 0
          -- Tiled rotates tile objects about their bottom-left anchor
          -- (degrees, clockwise on screen); work out the rotated bounding
          -- box so the entity occupies the tile the author sees in Tiled
          local rot = math.floor(((o.rotation or 0) % 360) / 90 + 0.5) * 90
          if o.gid then
            if rot ~= 0 then
              local rad = math.rad(rot)
              local cs, sn = math.cos(rad), math.sin(rad)
              local w = o.width or ts.tileheight
              local h = o.height or ts.tilewidth
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
              wy = wy - (o.height or ts.tileheight)
            end
          elseif o.width == nil and o.height == nil then
            wy = wy - ts.tileheight  -- point objects: feet at the point
          end
          local g = p.group
          if g == nil and o.name and o.name ~= "" then
            local n = o.name
            if #n > #kind
            and n:lower():sub(1, #kind + 1) == kind .. "_" then
              g = n:sub(#kind + 2)      -- "key_01" -> group "01"
            else
              g = n
            end
          end
          local ent = {
            kind = kind, x = wx, y = wy, g = g, name = o.name,
            spr = (t and t >= 0 and t < n_tiles) and t or nil,
            rot = rot ~= 0 and rot or nil,
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
            .. tostring(t) .. " has none, and its Class is not a kind); "
            .. "ignored")
        end
      end
    end
  end

  for label in pairs(skipped_kinds) do
    print("tiled: note - object '" .. label .. "' has no resolvable kind "
      .. "(no 'kind' property, its tile has none, and its Class is not a "
      .. "kind); ignored")
  end

  -- serialize to the game's map format: one hex byte per tile, row-major
  local rows = {}
  for r = 0, H - 1 do
    local buf = {}
    for c = 1, W do
      buf[c] = string.format("%02x", cells[(r) * W + c] or 0)
    end
    rows[r + 1] = table.concat(buf)
  end

  return {
    MAP_W = W,
    MAP_H = H,
    map   = rows,          -- array of hex row strings (game's mget format)
    gff   = gff,           -- per-tile flag bytes (bit0 solid, 1 sticky, 2 friction)
    special = special,     -- kind name -> tile id
    phase_tiles = phase_by_tile, -- tile ids flagged "phase" (switch-flipped platforms)
    slope_type = slope_type,
    objects = objects,     -- entities placed as objects on object layers
    map_layers = m.layers, -- raw layer list (tools/tests may inspect it)
    tileset_image = ts.image,
  }
end

return tiled
