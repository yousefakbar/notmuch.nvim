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

---Apply changes to snapshotted IDs, never to text or shifted row positions.
local function mutate(changes, first, last, remove)
  local search = require("notmuch.search")
  local buf = v.nvim_get_current_buf()
  local records = search.selected(buf, first, last)
  if #records == 0 then
    return
  end
  search.before_mutation(buf)
  local db
  local succeeded, errors = {}, {}
  local ok, err = pcall(function()
    db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
    for _, record in ipairs(records) do
      local done, failure = pcall(function()
        local threads = db.create_query("thread:" .. record.thread).get_threads()
        local thread = threads and threads[1]
        assert(thread, "Thread no longer exists: " .. record.thread)
        local current = thread:get_tags()
        for _, change in ipairs(changes) do
          local op, tag = change[1], change[2]
          if op == "remove" or (op == "toggle" and current[tag]) then
            thread:rm_tag(tag)
            current[tag] = nil
          else
            thread:add_tag(tag)
            current[tag] = true
          end
        end
        -- A fresh query avoids cached tag unions in libnotmuch thread objects.
        local fresh = db.create_query("thread:" .. record.thread).get_threads()[1]
        record.tags = vim.tbl_keys(fresh:get_tags())
        table.sort(record.tags)
        succeeded[record.thread] = true
      end)
      if not done then
        errors[#errors + 1] = tostring(failure)
      end
    end
  end)
  if db then
    local closed, close_err = pcall(db.close)
    if not closed then
      errors[#errors + 1] = tostring(close_err)
    end
  end
  if not ok then
    errors[#errors + 1] = tostring(err)
  end
  if remove then
    search.remove(buf, succeeded)
  else
    search.draw(buf)
  end
  if #errors > 0 then
    vim.notify(
      "notmuch.nvim: tag operation failed: " .. table.concat(errors, "\n"):sub(1, 2000),
      vim.log.levels.ERROR
    )
    search.refresh(buf)
  end
end

local function changes_for(op, tags)
  local changes = {}
  for _, tag in ipairs(u.split(tags, "%S+")) do
    changes[#changes + 1] = { op, tag }
  end
  return changes
end

t.thread_add_tag = function(tags, first, last)
  mutate(changes_for("add", tags), first, last)
end

t.thread_rm_tag = function(tags, first, last)
  mutate(changes_for("remove", tags), first, last)
end

t.thread_toggle_tag = function(tags, first, last)
  mutate(changes_for("toggle", tags), first, last)
end

t.delete_threads = function(first, last)
  mutate({ { "add", "del" }, { "remove", "inbox" } }, first, last, true)
end

return t

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
