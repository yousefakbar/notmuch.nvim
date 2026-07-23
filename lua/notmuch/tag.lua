local t = {}
local v = vim.api
local thread = require("notmuch.thread")
local u = require("notmuch.util")

local config = require("notmuch.config")

t.msg_add_tag = function(tags)
  local id = thread.get_current_message_id()
  if id == nil then
    return
  end

  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  local msg = db.get_message(id)
  for _, tag in pairs(t) do
    msg:add_tag(tag)
  end
  db.close()
  print("+(" .. tags .. ")")
end

t.msg_rm_tag = function(tags)
  local id = thread.get_current_message_id()
  if id == nil then
    return
  end

  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  local msg = db.get_message(id)
  for _, tag in pairs(t) do
    msg:rm_tag(tag)
  end
  db.close()
  print("-(" .. tags .. ")")
end

t.msg_toggle_tag = function(tags)
  local id = thread.get_current_message_id()
  if id == nil then
    return
  end

  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  local msg = db.get_message(id)
  local curr_tags = msg:get_tags()
  for _, tag in pairs(t) do
    if curr_tags[tag] == true then
      msg:rm_tag(tag)
      print("-" .. tag)
    else
      msg:add_tag(tag)
      print("+" .. tag)
    end
  end
  db.close()
end

local function thread_from_line(db, linenr)
  local line = vim.fn.getline(linenr)
  local threadid = line:match("^thread:(%S+)")
  if not threadid then
    return nil
  end

  local query = db.create_query("thread:" .. threadid)
  local threads = query.get_threads()
  return threads and threads[1]
end

t.thread_add_tag = function(tags, startlinenr, endlinenr)
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local thread = thread_from_line(db, linenr)
    if thread then
      for _, tag in pairs(t) do
        thread:add_tag(tag)
      end
    end
  end
  db.close()
  print("+(" .. tags .. ")")
end

t.thread_rm_tag = function(tags, startlinenr, endlinenr)
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local thread = thread_from_line(db, linenr)
    if thread then
      for _, tag in pairs(t) do
        thread:rm_tag(tag)
      end
    end
  end
  db.close()
  print("-(" .. tags .. ")")
end

t.thread_toggle_tag = function(tags, startlinenr, endlinenr)
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, "%S+")
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local thread = thread_from_line(db, linenr)
    if thread then
      local curr_tags = thread:get_tags()
      for _, tag in pairs(t) do
        if curr_tags[tag] == true then
          thread:rm_tag(tag)
          print("-" .. tag)
        else
          thread:add_tag(tag)
          print("+" .. tag)
        end
      end
    end
  end
  db.close()
end

return t

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
