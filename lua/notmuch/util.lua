local u = {}

u.print_table = function(tab)
  for k,v in pairs(tab) do
    print(v)
  end
end

u.capture = function(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local out = assert(f:read('*a')) -- *a means all content of pipe/file
  f:close()
  return out
end

u.split = function(s, delim)
  local out = {}
  local i = 1
  for entry in string.gmatch(s, delim) do
    out[i] = entry
    i = i + 1
  end
  return out
end

return u

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
