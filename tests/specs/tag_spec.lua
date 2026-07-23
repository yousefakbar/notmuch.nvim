local H = dofile("tests/helpers.lua")

local function with_mock_cnotmuch(state, fn)
  local old_loaded = package.loaded["notmuch.cnotmuch"]
  local dbs = {}

  package.loaded["notmuch.cnotmuch"] = function(path, mode)
    local db
    db = {
      path = path,
      mode = mode,
      closed = false,
      get_message = function(id)
        state.message_ids[#state.message_ids + 1] = id
        return state.messages[id]
      end,
      create_query = function(query)
        state.queries[#state.queries + 1] = query
        local id = query:match("^thread:(.+)$")
        return {
          get_threads = function()
            return state.threads[id] and { state.threads[id] } or {}
          end,
        }
      end,
      close = function()
        db.closed = true
        state.closed = state.closed + 1
      end,
    }
    dbs[#dbs + 1] = db
    return db
  end

  local ok, err = pcall(function()
    fn(dbs)
  end)
  package.loaded["notmuch.cnotmuch"] = old_loaded
  if not ok then
    error(err, 0)
  end
end

local function message(initial_tags)
  local m = { added = {}, removed = {}, tags = vim.deepcopy(initial_tags or {}) }
  function m:add_tag(tag)
    self.added[#self.added + 1] = tag
    self.tags[tag] = true
  end
  function m:rm_tag(tag)
    self.removed[#self.removed + 1] = tag
    self.tags[tag] = nil
  end
  function m:get_tags()
    return self.tags
  end
  return m
end

local function thread(initial_tags)
  return message(initial_tags)
end

local function with_current_message_id(id, fn)
  local thread_mod = require("notmuch.thread")
  local old = thread_mod.get_current_message_id
  thread_mod.get_current_message_id = function()
    return id
  end
  local ok, err = pcall(fn)
  thread_mod.get_current_message_id = old
  if not ok then
    error(err, 0)
  end
end

local function silence_print(fn)
  local old_print = print
  print = function() end
  local ok, err = pcall(fn)
  print = old_print
  if not ok then
    error(err, 0)
  end
end

return {
  {
    name = "tag message add/remove/toggle supports multiple tags and closes writable DB",
    run = function()
      local tag = require("notmuch.tag")
      local msg = message({ existing = true })
      local state =
        { messages = { msg1 = msg }, message_ids = {}, threads = {}, queries = {}, closed = 0 }

      with_mock_cnotmuch(state, function(dbs)
        with_current_message_id("msg1", function()
          silence_print(function()
            tag.msg_add_tag("one two")
            tag.msg_rm_tag("three four")
            tag.msg_toggle_tag("existing missing")
          end)
        end)
        H.eq(3, #dbs)
        H.eq(1, dbs[1].mode)
        H.same({ "msg1", "msg1", "msg1" }, state.message_ids)
        H.same({ "one", "two", "missing" }, msg.added)
        H.same({ "three", "four", "existing" }, msg.removed)
        H.eq(3, state.closed)
      end)
    end,
  },
  {
    name = "tag message operations return safely when no current message id exists",
    run = function()
      local tag = require("notmuch.tag")
      local state = { messages = {}, message_ids = {}, threads = {}, queries = {}, closed = 0 }
      local opened = false

      local old_loaded = package.loaded["notmuch.cnotmuch"]
      package.loaded["notmuch.cnotmuch"] = function()
        opened = true
        error("database should not be opened without a message id")
      end

      with_current_message_id(nil, function()
        tag.msg_add_tag("one")
        tag.msg_rm_tag("one")
        tag.msg_toggle_tag("one")
      end)

      H.eq(false, opened)
      H.eq(0, state.closed)
      package.loaded["notmuch.cnotmuch"] = old_loaded
    end,
  },
  {
    name = "tag thread add/remove/toggle operates on ranges and skips malformed lines",
    run = function()
      local tag = require("notmuch.tag")
      local t1 = thread({ inbox = true })
      local t2 = thread({})
      local state = {
        messages = {},
        message_ids = {},
        queries = {},
        closed = 0,
        threads = { abc = t1, def = t2 },
      }
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Hints: ignore me",
        "thread:abc  today [1/1] subject",
        "not a thread line",
        "thread:def  today [1/1] subject",
      })

      with_mock_cnotmuch(state, function()
        silence_print(function()
          tag.thread_add_tag("one two", 2, 4)
          tag.thread_rm_tag("old gone", 2, 4)
          tag.thread_toggle_tag("inbox flagged", 2, 4)
        end)
      end)

      H.same(
        { "thread:abc", "thread:def", "thread:abc", "thread:def", "thread:abc", "thread:def" },
        state.queries
      )
      H.same({ "one", "two", "flagged" }, t1.added)
      H.same({ "old", "gone", "inbox" }, t1.removed)
      H.same({ "one", "two", "inbox", "flagged" }, t2.added)
      H.same({ "old", "gone" }, t2.removed)
      H.eq(3, state.closed)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "tag thread operation defaults to current line",
    run = function()
      local tag = require("notmuch.tag")
      local t1 = thread({})
      local state =
        { messages = {}, message_ids = {}, queries = {}, closed = 0, threads = { abc = t1 } }
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "thread:abc  subject" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      with_mock_cnotmuch(state, function()
        silence_print(function()
          tag.thread_add_tag("current")
        end)
      end)

      H.same({ "current" }, t1.added)
      H.same({ "thread:abc" }, state.queries)
      H.eq(1, state.closed)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
  {
    name = "tag archive/read keybindings mutate selected thread tags directly",
    run = function()
      local archive = thread({ inbox = true })
      local archive_read = thread({ inbox = true, unread = true })
      local read = thread({ unread = true })
      local flag = thread({})
      local state = {
        messages = {},
        message_ids = {},
        queries = {},
        closed = 0,
        threads = {
          archive = archive,
          archive_read = archive_read,
          read = read,
          flag = flag,
        },
      }

      local buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "thread:archive  subject",
        "thread:archive_read  subject",
        "thread:read  subject",
        "thread:flag  subject",
      })
      vim.bo.filetype = "notmuch-threads"
      vim.cmd("runtime ftplugin/notmuch-threads.lua")

      local function press(line, key)
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
        silence_print(function()
          vim.api.nvim_feedkeys(keys, "x", false)
        end)
      end

      with_mock_cnotmuch(state, function()
        press(1, "a") -- toggle inbox off
        press(2, "A") -- remove inbox and unread
        press(3, "x") -- toggle unread off
        press(4, "f") -- toggle flagged on
      end)

      H.same({ "inbox" }, archive.removed)
      H.same({ "inbox", "unread" }, archive_read.removed)
      H.same({ "unread" }, read.removed)
      H.same({ "flagged" }, flag.added)
      H.same({
        "thread:archive",
        "thread:archive_read",
        "thread:read",
        "thread:flag",
      }, state.queries)
      H.eq(4, state.closed)

      vim.api.nvim_buf_delete(buf, { force = true })
    end,
  },
}
