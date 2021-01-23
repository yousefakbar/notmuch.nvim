local nm = {}
local v = vim.api
local f = require'notmuch.float'

local buf_stack = {}

local function capture(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local out = assert(f:read('*a')) -- *a means all content of pipe/file
  f:close()
  return out
end

local function split(s)
  local lines = {}
  local i = 1
  for entry in string.gmatch(s, "%C+") do
    lines[i] = entry
    i = i + 1
  end
  return lines
end

nm.search_tag = function(tag)
  print(tag)
  local buf = v.nvim_create_buf(false, true)
  v.nvim_buf_set_name(buf, "Threads")
  --v.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  v.nvim_win_set_buf(0, buf)
  local out = split(capture("notmuch search tag:" .. tag))
  v.nvim_buf_set_lines(0, 0, 0, true, out)
  vim.bo.filetype = "notmuch-threads"
  v.nvim_del_current_line()
  v.nvim_input("gg")
end

-- TODO: implement folding for each message in a thread
-- User presses <CR> on a thread, pass the line to this function
nm.show_thread = function()
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, "[0-9a-z]+", 7)
  local text = capture("notmuch show --format=text thread:" .. threadid)
  local float = f.open_floating_window()
  v.nvim_buf_set_lines(0, 0, 0, true, split(text))
  vim.bo.filetype="mail"
  v.nvim_input("gg")
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab
