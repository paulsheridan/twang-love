-- src/tiled.lua: load Tiled (mapeditor.org) JSON maps for twang.
--
-- Editing conventions (tile properties, entity objects, puzzle groups)
-- are documented in docs/tiled-format.md. In brief:
--
-- * 8x8 orthogonal map referencing any number of tilesets, each with
--   its own image and column count. A 8x8 tileset is TERRAIN (its tiles
--   carry gameplay flags and paint the collision grid); a 16x16
--   tileset is CHARACTER ART (its tiles are placed as objects).
--   External tilesets (.tsx) are resolved from files next to the map
-- * every referenced gid resolves to a self-contained tile record
--   (source rect in its own image + its own flags), so two levels may
--   use entirely different art without any shared id space
-- * per-tile custom properties drive the game: solid, bounce (arrows
--   reflect off it instead of embedding), friction, arrow_pass,
--   runnable, oneway, phase (switch-flipped platforms) and kind (entity
--   role). "sticky" is a legacy spelling of "bounce" kept for the old
--   spritesheet tileset: either name makes arrows reflect.
-- * a 16x16 tile with a "kind" property supplies that role's art by
--   name (level.art[kind]); "on_id"/"ext_id" name a sibling tile in the
--   same tileset for the switch-on / spring-extended states
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

local ART = 16  -- entity art cell (px): object anchors & hit boxes

-- The vocabulary of entity roles an object may claim, by "kind"
-- property or Class field. This is the game's vocabulary, not art: what
-- each role LOOKS like comes from the tileset tile that carries the
-- kind, so the two are free to change independently.
local KINDS = {
  "spawn", "key", "lock", "door", "switch", "spring", "winch", "gun",
  "pusher", "updraft", "outdraft", "mover", "mover_trigger", "movertrigger",
  "exit", "checkpoint",
  "archer", "melee", "laser", "rocketeer", "bomber",
}
local KIND_NAMES = {}
for _, name in ipairs(KINDS) do KIND_NAMES[name] = true end

local tiled = {
  KINDS  = KINDS,   -- exported for tools (the role vocabulary)
  ART    = ART,     -- exported for tools
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
-- per-tile custom properties; everything else in the file is ignored.
-- Tiled has two shapes: a SHEET (one <image>, tiles cut from it by
-- source rect) and a COLLECTION (each <tile> carries its own <image>).
-- Both are supported; `tsx.collection` tells them apart.
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
    local tile = { id = n, properties = props }
    -- a collection tileset: this tile has an image of its own
    local timg = body:match("<image[^>]*>")
    if timg then
      local a = {}
      for k, v in timg:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do a[k] = v end
      tile.image = xml_unescape(a.source or "")
      tile.imagewidth = tonumber(a.width)
      tile.imageheight = tonumber(a.height)
      tsx.collection = true
    end
    tsx.tiles[n + 1] = tile
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

-- The source rect of a tile within its tileset image. `columns` is the
-- tileset's own column count, so this works for any geometry; margin
-- and spacing are honoured for hand-authored sheets.
local function source_rect(ts, id)
  local m, sp = ts.margin or 0, ts.spacing or 0
  local col = id % ts.columns
  local row = math.floor(id / ts.columns)
  return m + col * (ts.tilewidth + sp), m + row * (ts.tileheight + sp)
end

-- A .tsx names its image relative to ITSELF, but love.filesystem and
-- newImage want it relative to the game root. Join the two and collapse
-- "." and ".." so "maps/" + "../sheet.png" becomes "sheet.png".
local function rooted_path(dir, source)
  if source == nil then return nil end
  if source:match("^%a:[/\\]") or source:sub(1, 1) == "/" then
    return source  -- already absolute
  end
  local parts = {}
  for part in (dir .. source):gmatch("[^/\\]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end

-- Loads a standalone 16x16 art tileset (no map) and returns its tiles
-- keyed by their "kind" property. This is the global character art: the
-- player animation frames and HUD icons, which are the same across
-- levels. A level restyles any of these roles by declaring the same
-- kind in one of its own tilesets.
function tiled.load_artset(path)
  local ts = parse_tsx(read_file(path))
  local dir = path:match("^(.-)[^/\\]*$") or ""
  assert(ts.tilewidth == ART and ts.tileheight == ART,
    "tiled: the character art tileset must be " .. ART .. "x" .. ART
    .. " (got " .. tostring(ts.tilewidth) .. "x" .. tostring(ts.tileheight)
    .. ") in " .. path)
  if not ts.columns then
    ts.columns = math.floor((ts.imagewidth - 2 * (ts.margin or 0))
                            / ts.tilewidth)
  end
  ts.image = rooted_path(dir, ts.image)
  local art = {}
  for _, tt in pairs(ts.tiles or {}) do
    local p = prop_map(tt.properties)
    if p.kind then
      local sx, sy = source_rect(ts, tt.id)
      art[p.kind] = {
        image = ts.image, columns = ts.columns, id = tt.id, sx = sx, sy = sy,
        w = ART, h = ART, kind = p.kind,
      }
    end
  end
  return art
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

  -- Tilesets: any number, each with its own image and geometry. An 8px
  -- tileset is TERRAIN (paints the collision grid, carries the gameplay
  -- flags); a 16px tileset is CHARACTER ART (placed as objects). Gids
  -- are dispatched to whichever tileset's firstgid range they fall in.
  assert(m.tilesets and #m.tilesets >= 1,
    "tiled: the map must reference at least one tileset")
  local sets = {}
  -- the map's own directory, for resolving a .tsx's relative image
  local dir = path:match("^(.-)[^/\\]*$") or ""
  for _, ref in ipairs(m.tilesets) do
    local ts = ref
    if ref.source then
      -- external tileset (.tsx next to the map)
      ts = parse_tsx(read_file(dir .. ref.source))
      ts.firstgid = ref.firstgid
    end
    assert(ts.tilewidth and ts.tileheight,
      "tiled: a tileset in " .. path .. " declares no tile size")
    if ts.tilewidth == 8 and ts.tileheight == 8 then
      ts.terrain = true
    elseif ts.tilewidth == ART and ts.tileheight == ART then
      ts.terrain = false
    else
      error("tiled: unsupported tileset geometry "
        .. tostring(ts.tilewidth) .. "x" .. tostring(ts.tileheight)
        .. " in " .. path .. " (expected 8x8 terrain or 16x16 art)")
    end
    -- Tiled omits `columns` only for a single-row sheet tileset; derive
    -- it from the image otherwise so hand-written .tsx files still load.
    -- A COLLECTION has no sheet at all: every tile brings its own image.
    if ts.collection then
      ts.columns = ts.columns or 1
      ts.tilecount = ts.tilecount or #ts.tiles
      ts.image = nil
    else
      if not ts.columns then
        assert(ts.imagewidth and ts.imageheight and ts.image,
          "tiled: tileset " .. tostring(ts.name or ts.firstgid)
          .. " in " .. path .. " has neither columns nor an image size")
        ts.columns = math.floor((ts.imagewidth - 2 * (ts.margin or 0))
                                / ts.tilewidth)
      end
      assert(ts.image, "tiled: tileset " .. tostring(ts.name or ts.firstgid)
        .. " in " .. path .. " has no <image> and is not a collection of "
        .. "per-tile images")
      local n = ts.tilecount or math.floor(
        (ts.imageheight - 2 * (ts.margin or 0)) / ts.tileheight) * ts.columns
      assert(n and n > 0,
        "tiled: tileset " .. tostring(ts.name or ts.firstgid)
        .. " in " .. path .. " has no tiles (needs tilecount or an image)")
      ts.tilecount = n
      ts.image = rooted_path(dir, ts.image)
    end
    if ts.collection then
      -- each tile's own image, resolved against the .tsx
      for _, tt in pairs(ts.tiles) do
        if tt.image then tt.image = rooted_path(dir, tt.image) end
      end
    end
    sets[#sets + 1] = ts
  end
  -- sort by firstgid so gid dispatch is a single ordered scan
  table.sort(sets, function(a, b) return a.firstgid < b.firstgid end)

  -- The resolved tile table: one entry per distinct (tileset, local id)
  -- the map actually references, flattened into a dense array. Each
  -- entry carries its own source rect and flags, so nothing downstream
  -- needs to know which tileset or sheet a tile came from.
  local tiles, gid_to_tile = {}, {}

  -- Resolves a gid to a tile record, or nil (with a warning) when it
  -- falls in no tileset or names a tile the set does not contain.
  local function resolve(gid, ctx)
    local set
    for _, s in ipairs(sets) do
      if gid >= s.firstgid and gid < s.firstgid + s.tilecount then
        set = s
        break
      end
    end
    if not set then
      print("tiled: warning - " .. ctx .. " GID " .. tostring(gid)
        .. " falls in no tileset; ignored")
      return nil
    end
    local id = gid - set.firstgid
    local key = set.firstgid + id
    local rec = gid_to_tile[key]
    if rec then return rec end
    local sx, sy = source_rect(set, id)
    local tile_img = set.image
    if set.collection then
      -- a collection tile is its own image: no source rect to cut
      for _, tt in pairs(set.tiles or {}) do
        if tt.id == id and tt.image then tile_img = tt.image end
      end
      sx, sy = 0, 0
    end
    rec = {
      image   = tile_img,
      columns = set.columns,
      id      = id,
      sx      = sx,
      sy      = sy,
      w = set.tilewidth, h = set.tileheight,
      terrain = set.terrain or nil,
      key     = key,
    }
    -- (pairs: the tiles array is sparse -- one slot per local tile id)
    for _, tt in pairs(set.tiles or {}) do
      if tt.id == id then
        local p = prop_map(tt.properties)
        if p.solid      then rec.solid = true end
        -- "bounce" is the name levels author; "sticky" is the legacy
        -- spelling the old spritesheet tileset uses for the same thing.
        -- Both land on one flag, so arrows reflect either way.
        if p.bounce or p.sticky then rec.bounce = true end
        if p.friction   then rec.friction = true end
        if p.arrow_pass then rec.arrow_pass = true end
        if p.runnable   then rec.runnable = true end
        if p.oneway     then rec.oneway = true end
        if p.phase      then rec.phase = true end
        rec.kind    = p.kind
        rec.on_id   = p.on_id
        rec.ext_id  = p.ext_id
      end
    end
    tiles[#tiles + 1] = rec
    gid_to_tile[key] = rec
    return rec
  end

  -- Art by role name, gathered from every tileset that declares a
  -- "kind" property. A role's art is simply the tile carrying it, so a
  -- level swaps its whole cast by swapping tilesets.
  local art = {}
  for _, set in ipairs(sets) do
    if not set.terrain then
      for _, tt in pairs(set.tiles or {}) do
        local p = prop_map(tt.properties)
        if p.kind and KIND_NAMES[p.kind] then
          local rec = resolve(set.firstgid + tt.id, "tileset " ..
            tostring(set.name or set.firstgid) .. " art")
          art[p.kind] = rec
          -- the switch-on / spring-extended states are sibling tiles in
          -- the same set, named by id so the pair travels together
          if p.on_id then
            art[p.kind .. "_on"] = resolve(set.firstgid + tonumber(p.on_id),
              "tileset art " .. p.kind .. " on_id")
          end
          if p.ext_id then
            art[p.kind .. "_ext"] = resolve(set.firstgid + tonumber(p.ext_id),
              "tileset art " .. p.kind .. " ext_id")
          end
        end
      end
    end
  end

  local has_terrain = false
  for _, s in ipairs(sets) do if s.terrain then has_terrain = true end end
  assert(has_terrain, "tiled: the map has no 8px terrain tileset in " .. path)

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
        local rec = resolve(gid, "terrain cell")
        -- only terrain tiles may paint the collision grid; a 16px art
        -- tile dropped in a tile layer has no meaning here
        if rec and not rec.terrain then
          print("tiled: warning - terrain cell uses 16x16 art gid " .. gid
            .. " (terrain layers take 8x8 tiles only); ignored")
        elseif rec then
          into[i] = rec.key
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

  -- A level whose terrain carries no gameplay flags at all is worth saying
  -- out loud: every tile in it is pure paint, so nothing is solid, nothing
  -- bounces, and the player walks straight through all of it. The usual
  -- cause is a tileset edit that was never saved -- Tiled writes per-tile
  -- properties into the TILESET file, which for an external .tsx is a
  -- separate save from the map (docs/tiled-format.md).
  do
    local placed, flagged, sample = 0, 0
    for i = 1, W * H do
      local key = cells[i]
      if key and key ~= 0 then
        placed = placed + 1
        local rec = gid_to_tile[key]
        if rec and (rec.solid or rec.bounce or rec.friction or rec.arrow_pass
                    or rec.runnable or rec.oneway or rec.phase) then
          flagged = flagged + 1
        elseif rec and not sample then
          sample = key
        end
      end
    end
    if placed > 0 and flagged == 0 then
      local names = {}
      for _, ref in ipairs(m.tilesets or {}) do
        names[#names + 1] = ref.source or ("embedded tileset at firstgid "
          .. tostring(ref.firstgid))
      end
      print("tiled: note - " .. path .. ": all " .. placed
        .. " terrain cells carry no tile properties, so nothing here is "
        .. "solid (or bounce) and the player passes through everything. "
        .. "If you just flagged tiles solid in Tiled, the tileset ("
        .. table.concat(names, ", ")
        .. ") still has no <properties> saved -- it is a separate file from "
        .. "the map, save it too. An unflagged tile, for reference: gid "
        .. tostring(sample))
    end
  end

  -- object layers hold all entities: tile objects whose role comes from
  -- a kind property / the placed tile's kind / the Class field, grouped
  -- by name (with a "<kind>_" prefix stripped) or a "group" property
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
          local tw, th = m.tilewidth, m.tileheight
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
          -- object art: the placed tile IS the art (any tileset, 8px or
          -- 16px); its "kind" property names the role. A plain object
          -- with no gid falls back to the role's art by name.
          local gid = o.gid
          local tile, kind
          if gid then
            -- Tiled flips the high bit of gid for y-flipped objects
            tile = resolve(gid % 0x20000000, "object '" .. tostring(o.name) .. "'")
            kind = tile and tile.kind
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
              -- the placed tile if it had one, else the role's art by
              -- name: either way the entity draws from this record
              art = tile or art[kind] or art[kind .. "_on"] or art[kind .. "_ext"],
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
    if covered < W * H * m.tilewidth * m.tileheight then
      print("tiled: note - rooms do not cover the whole map; uncovered "
        .. "areas clamp the camera to the whole map")
    end
  end

  -- serialize to the game's map format: four hex digits per 8px tile,
  -- row-major. The value is the tile's key -- its gid, unique across
  -- every tileset the map references -- which indexes `tiles_by_key`.
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
    -- gid -> tile record. Every grid value, phase query and solidity
    -- check resolves through this table; a nil entry means empty.
    tiles_by_key = gid_to_tile,
    art   = art,           -- role name -> art tile record
    objects = objects,     -- entities placed as objects on object layers
    rooms = #rooms > 0 and rooms or nil, -- "room" rectangles (camera frames)
    map_layers = m.layers, -- raw layer list (tools/tests may inspect it)
    -- every image this level's art lives in, de-duplicated: the renderer
    -- preloads these once per level load
    images = (function()
      local seen, list = {}, {}
      for _, rec in pairs(gid_to_tile) do
        if rec.image and not seen[rec.image] then
          seen[rec.image] = true
          list[#list + 1] = rec.image
        end
      end
      return list
    end)(),
  }
end

return tiled
