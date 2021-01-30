local t = {}
local v = vim.api
local u = require'notmuch.util'

local function find_cursor_msg_id()
  local n = v.nvim_win_get_cursor(0)[1] + 1
  local line = nil
  local id = nil
  while n ~= 1 do
    line = vim.fn.getline(n)
    if string.match(line, '^id:%S+ {{{$') ~= nil then
      id = string.match(line, '%S+', 4)
      return id
    end
    n = n - 1
  end
  return nil
end

t.msg_add_tag = function(tags)
  local tags_mod = string.gsub(tags, '%s+(%w+)', ' +%1')
  local id = find_cursor_msg_id()
  os.execute('notmuch tag +' .. tags_mod .. ' -- id:' .. id)
  print('+' .. tags_mod)
end

t.msg_rm_tag = function(tags)
  local tags_mod = string.gsub(tags, '%s+(%w+)', ' -%1')
  local id = find_cursor_msg_id()
  os.execute('notmuch tag -' .. tags_mod .. ' -- id:' .. id)
  print('-' .. tags_mod)
end

t.msg_toggle_tag = function(tags)
  local tags_table = u.split(tags, "%S+")
  local id = find_cursor_msg_id()
  local curr_tags = u.capture('notmuch search --output=tags -- id:' .. id)
  for k,tag in pairs(tags_table) do
    if string.find(curr_tags, tag) ~= nil then
      t.msg_rm_tag(tag)
    else
      t.msg_add_tag(tag)
    end
  end
end

t.thread_add_tag = function(tags)
  local tags_mod = string.gsub(tags, '%s+(%w+)', ' +%1')
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  os.execute('notmuch tag +' .. tags_mod .. ' -- thread:' .. threadid)
  print('+' .. tags_mod)
end

t.thread_rm_tag = function(tags)
  local tags_mod = string.gsub(tags, '%s+(%w+)', ' -%1')
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  os.execute('notmuch tag -' .. tags_mod .. ' -- thread:' .. threadid)
  print('-' .. tags_mod)
end

t.thread_toggle_tag = function(tags)
  local tags_table = u.split(tags, "%S+")
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  local curr_tags = u.capture('notmuch search --output=tags -- thread:' .. threadid)
  for k,tag in pairs(tags_table) do
    if string.find(curr_tags, tag) ~= nil then
      t.thread_rm_tag(tag)
    else
      t.thread_add_tag(tag)
    end
  end
end

return t

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
