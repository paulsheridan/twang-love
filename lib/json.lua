-- json.lua: minimal JSON encoder/decoder.
-- Pure Lua (5.1 / LuaJIT compatible), no dependencies. Sufficient for
-- Tiled map files: objects, arrays, strings (with \uXXXX incl. surrogate
-- pairs), numbers, booleans and null. Object keys are emitted sorted so
-- output is deterministic.

local json = {}

-- ===== encoding =====

local escapes = {
  ['"']  = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function quote(s)
  local body = s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format('\\u%04x', c:byte())
  end)
  return '"' .. body .. '"'
end

local function num2str(n)
  if n ~= n or n == math.huge or n == -math.huge then return 'null' end
  if n % 1 == 0 and math.abs(n) < 2^53 then
    return string.format('%d', n)
  end
  return string.format('%.14g', n)
end

-- a table is an array if every key is a 1..n integer (empty tables encode
-- as [])
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k <= 0 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

local encode_value

local function encode_scalar(v)
  local t = type(v)
  if     t == 'string'  then return quote(v)
  elseif t == 'number'  then return num2str(v)
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'nil'     then return 'null'
  else error('json.encode: unsupported value of type ' .. t) end
end

encode_value = function(v, ind, out)
  local t = type(v)
  if t ~= 'table' then
    out[#out + 1] = encode_scalar(v)
    return
  end
  if is_array(v) then
    local n = #v
    if n == 0 then out[#out + 1] = '[]' return end
    local allscalar = true
    for i = 1, n do
      if type(v[i]) == 'table' then allscalar = false break end
    end
    if allscalar then
      -- keep e.g. tile-layer data compact: chunks of 16 per line
      out[#out + 1] = '[ '
      for i = 1, n do
        if i > 1 then
          if (i - 1) % 16 == 0 then out[#out + 1] = '\n' .. ind .. '  ' end
          out[#out + 1] = ', '
        end
        out[#out + 1] = encode_scalar(v[i])
      end
      out[#out + 1] = ' ]'
    else
      out[#out + 1] = '[\n'
      for i = 1, n do
        out[#out + 1] = ind .. '  '
        encode_value(v[i], ind .. '  ', out)
        out[#out + 1] = i < n and ',\n' or '\n'
      end
      out[#out + 1] = ind .. ']'
    end
  else
    local keys = {}
    for k in pairs(v) do
      if type(k) ~= 'string' then
        error('json.encode: object keys must be strings')
      end
      keys[#keys + 1] = k
    end
    if #keys == 0 then out[#out + 1] = '{}' return end
    table.sort(keys)
    out[#out + 1] = '{\n'
    for i, k in ipairs(keys) do
      out[#out + 1] = ind .. '  ' .. quote(k) .. ': '
      encode_value(v[k], ind .. '  ', out)
      out[#out + 1] = i < #keys and ',\n' or '\n'
    end
    out[#out + 1] = ind .. '}'
  end
end

function json.encode(v)
  local out = {}
  encode_value(v, '', out)
  return table.concat(out)
end

-- ===== decoding =====

local function err(pos, msg)
  error(string.format('json: %s at byte %d', msg, pos), 0)
end

local function ws(s, p)
  while true do
    local c = s:byte(p)
    if c == 32 or c == 9 or c == 10 or c == 13 then p = p + 1 else return p end
  end
end

local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096),
      0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  else
    return string.char(0xF0 + math.floor(cp / 262144),
      0x80 + math.floor(cp / 4096) % 64,
      0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
end

local simple_escapes = {
  b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
}

local function decode_string(s, p) -- p at the opening quote
  local buf = {}
  local i = p + 1
  while true do
    local j = s:find('["\\]', i)
    if not j then err(p, 'unterminated string') end
    buf[#buf + 1] = s:sub(i, j - 1)
    if s:byte(j) == 34 then -- closing quote
      return table.concat(buf), j + 1
    end
    -- escape at j
    local e = s:sub(j + 1, j + 1)
    if simple_escapes[e] then
      buf[#buf + 1] = simple_escapes[e]
      i = j + 2
    elseif e == 'u' then
      local hex = s:sub(j + 2, j + 5)
      local cp = tonumber(hex, 16)
      if not cp then err(j, 'bad \\u escape') end
      i = j + 6
      -- combine a surrogate pair
      if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == '\\u' then
        local lo = tonumber(s:sub(i + 2, i + 5), 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          i = i + 6
        end
      end
      buf[#buf + 1] = utf8_encode(cp)
    else
      err(j, 'bad escape \\' .. e)
    end
  end
end

local number_patterns = {
  '^%-?%d+%.%d*[eE][-+]?%d+',
  '^%-?%d+%.%d*',
  '^%-?%d+[eE][-+]?%d+',
  '^%-?%d+',
}

local function decode_number(s, p)
  for _, pat in ipairs(number_patterns) do
    local lit = s:match(pat, p)
    if lit then return tonumber(lit), p + #lit end
  end
  err(p, 'bad number')
end

local decode_value

local function decode_object(s, p) -- p at '{'
  local obj = {}
  p = ws(s, p + 1)
  if s:byte(p) == 125 then return obj, p + 1 end -- }
  while true do
    p = ws(s, p)
    if s:byte(p) ~= 34 then err(p, 'expected string key') end
    local key
    key, p = decode_string(s, p)
    p = ws(s, p)
    if s:byte(p) ~= 58 then err(p, "expected ':'") end
    local v
    v, p = decode_value(s, p + 1)
    obj[key] = v
    p = ws(s, p)
    local c = s:byte(p)
    if c == 44 then p = p + 1          -- ,
    elseif c == 125 then return obj, p + 1
    else err(p, "expected ',' or '}'") end
  end
end

local function decode_array(s, p) -- p at '['
  local arr = {}
  p = ws(s, p + 1)
  if s:byte(p) == 93 then return arr, p + 1 end -- ]
  while true do
    local v
    v, p = decode_value(s, p)
    arr[#arr + 1] = v
    p = ws(s, p)
    local c = s:byte(p)
    if c == 44 then p = p + 1          -- ,
    elseif c == 93 then return arr, p + 1
    else err(p, "expected ',' or ']'") end
  end
end

decode_value = function(s, p)
  p = ws(s, p)
  local c = s:byte(p)
  if     c == 123 then return decode_object(s, p) -- {
  elseif c == 91  then return decode_array(s, p)  -- [
  elseif c == 34  then return decode_string(s, p) -- "
  elseif c == 116 then -- t
    if s:sub(p, p + 3) == 'true' then return true, p + 4 end
    err(p, 'bad literal')
  elseif c == 102 then -- f
    if s:sub(p, p + 4) == 'false' then return false, p + 5 end
    err(p, 'bad literal')
  elseif c == 110 then -- n
    if s:sub(p, p + 3) == 'null' then return nil, p + 4 end
    err(p, 'bad literal')
  else
    return decode_number(s, p)
  end
end

function json.decode(str)
  assert(type(str) == 'string', 'json.decode: expected a string')
  local v, p = decode_value(str, 1)
  p = ws(str, p)
  if p <= #str then err(p, 'trailing garbage') end
  return v
end

-- pico-8 style default export shape (require("json").decode / .encode)
return json
