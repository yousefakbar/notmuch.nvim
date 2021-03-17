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
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local id = find_cursor_msg_id()
  local msg = db.get_message(id)
  for i,tag in pairs(t) do
    msg:add_tag(tag)
  end
  db.close()
  print('+(' .. tags .. ')')
end

t.msg_rm_tag = function(tags)
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local id = find_cursor_msg_id()
  local msg = db.get_message(id)
  for i,tag in pairs(t) do
    msg:rm_tag(tag)
  end
  db.close()
  print('-(' .. tags .. ')')
end

t.msg_toggle_tag = function(tags)
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local id = find_cursor_msg_id()
  local msg = db.get_message(id)
  local curr_tags = msg:get_tags()
  for i,tag in pairs(t) do
    if curr_tags[tag] == true then
      msg:rm_tag(tag)
      print('-' .. tag)
    else
      msg:add_tag(tag)
      print('+' .. tag)
    end
  end
  db.close()
end

t.thread_add_tag = function(tags)
  local t = u.split(tags, '%S+')
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local query = db.create_query('thread:' .. threadid)
  local thread = query.get_threads()[1]
  for i,tag in pairs(t) do
    thread:add_tag(tag)
  end
  db.close()
  print('+(' .. tags .. ')')
end

t.thread_rm_tag = function(tags)
  local t = u.split(tags, '%S+')
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local query = db.create_query('thread:' .. threadid)
  local thread = query.get_threads()[1]
  for i,tag in pairs(t) do
    thread:rm_tag(tag)
  end
  db.close()
  print('-(' .. tags .. ')')
end

t.thread_toggle_tag = function(tags)
  local t = u.split(tags, '%S+')
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, '%S+', 8)
  local db = require'notmuch.cnotmuch'(vim.g.NotmuchDBPath, 1)
  local query = db.create_query('thread:' .. threadid)
  local thread = query.get_threads()[1]
  local curr_tags = thread:get_tags()
  for i,tag in pairs(t) do
    if curr_tags[tag] == true then
      thread:rm_tag(tag)
      print('-' .. tag)
    else
      thread:add_tag(tag)
      print('+' .. tag)
    end
  end
  db.close()
end

return t

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
