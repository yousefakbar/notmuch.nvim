local u = {}

u.capture = function(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local out = assert(f:read('*a')) -- *a means all content of pipe/file
  f:close()
  return out
end

u.split = function(s)
  local lines = {}
  local i = 1
  for entry in string.gmatch(s, "%C+") do
    lines[i] = entry
    i = i + 1
  end
  return lines
end

return u

-- vim: tabstop=2:shiftwidth=2:expandtab
