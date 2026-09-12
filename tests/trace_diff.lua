-- Compares two trace files produced by tests/run.lua and exits non-zero
-- on any difference.
--
-- Usage: luajit tests/trace_diff.lua tests/trace_legacy.txt tests/trace_refactor.txt

local a_path, b_path = arg[1], arg[2]
if not a_path or not b_path then
  error("usage: luajit tests/trace_diff.lua <trace-a> <trace-b>")
end

local function read_lines(path)
  local f = assert(io.open(path, "rb"))
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  return lines
end

local a, b = read_lines(a_path), read_lines(b_path)
local diffs = 0
for i = 1, math.max(#a, #b) do
  if a[i] ~= b[i] then
    diffs = diffs + 1
    if diffs <= 20 then
      print(("DIFF line %d:\n  legacy : %s\n  current: %s")
        :format(i, a[i] or "<eof>", b[i] or "<eof>"))
    end
  end
end
if diffs > 0 then
  print(("%d differing line(s)"):format(diffs))
  os.exit(1)
end
print("traces identical (" .. #a .. " lines)")
